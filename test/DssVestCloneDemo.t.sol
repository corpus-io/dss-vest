// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.17;

//import "ds-test/test.sol";
import "../lib/forge-std/src/Test.sol";
import "@opengsn/contracts/src/forwarder/Forwarder.sol";
import "@tokenize.it/contracts/contracts/Token.sol";
import "@tokenize.it/contracts/contracts/AllowList.sol";
import "@tokenize.it/contracts/contracts/FeeSettings.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {DssVest, DssVestMintable} from "../src/DssVest.sol";
import "../src/DssVestMintableCloneFactory.sol";


contract DssVestDemo is Test {
    uint256 constant totalVestAmount = 42e18; // 42 tokens
    uint256 constant vestDuration = 4 * 365 days; // 4 years
    uint256 constant vestCliff = 1 * 365 days; // 1 year

    // init forwarder
    Forwarder forwarder = new Forwarder();
    bytes32 domainSeparator;
    bytes32 requestType;

    // DO NOT USE THESE KEYS IN PRODUCTION! They were generated and stored very unsafely.
    uint256 public constant platformAdminPrivateKey =
        0x3c69254ad72222e3ddf37667b8173dd773bdbdfd93d4af1d192815ff0662de5f;
    address public platformAdminAddress = vm.addr(companyAdminPrivateKey); // = 0x38d6703d37988C644D6d31551e9af6dcB762E618;

    uint256 public constant companyAdminPrivateKey =
        0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a;
    address public companyAdminAddress = vm.addr(companyAdminPrivateKey); // = 0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC;

    uint256 public constant employeePrivateKey =
        0x8da4ef21b864d2cc526dbdb2a120bd2874c36c9d0a1fb7f8c63d7f7a8b41de8f;
    address public employeeAddress = vm.addr(employeePrivateKey); // = 0x63FaC9201494f0bd17B9892B9fae4d52fe3BD377;

    address public constant relayer =
        0xDFcEB49eD21aE199b33A76B726E2bea7A72127B0;

    address public constant platformFeeCollector =
        0x7109709eCfa91A80626Ff3989D68f67f5b1dD127;

    DssVestMintable          mVest;

    uint tokenFeeDenominator = 100;
    uint paymentTokenFeeDenominator = 200;
    Token companyToken;

    function setUp() public {

        vm.warp(60 * 365 days); // in local testing, the time would start at 1. This causes problems with the vesting contract. So we warp to 60 years.

        // create logic contract that will be cloned. 
        // Forwarder must be correct, but token address can be any address (not 0), as it will be replaced during cloning
        DssVestMintable logic = new DssVestMintable(address(forwarder), address(1), 0);

        // deploy factory contract
        DssVestMintableCloneFactory cloneFactory = new DssVestMintableCloneFactory(address(logic));

        // deploy tokenize.it platform and company token
        vm.startPrank(platformAdminAddress);
        AllowList allowList = new AllowList();
        Fees memory fees = Fees(
            tokenFeeDenominator,
            paymentTokenFeeDenominator,
            paymentTokenFeeDenominator,
            0
        );

        FeeSettings feeSettings = new FeeSettings(fees, platformFeeCollector);

        companyToken = new Token(
            address(forwarder),
            feeSettings,
            companyAdminAddress,
            allowList,
            0, // set requirements 0 in order to keep this test simple
            "Company Token",
            "COMPT"
        );
        vm.stopPrank();

        // can be any salt, as long as it is unique. Using the same salt twice will result in the same address and therefore the second clone creation will fail.
        bytes32 salt = bytes32(0);

        // predict address of clone in order to 
        // 1. check if a contract already lives at this address
        // 2. prepare further transactions with this information, like increasing Minting allowance
        address cloneAddress = cloneFactory.predictCloneAddress(salt);

        // important for real life: check if a contract already lives at this address. If that is the case, we cannot deploy a new clone with the same salt.
        // Address prediction function does not do this check!

        // grant minting allowance
        vm.prank(companyAdminAddress);
        companyToken.increaseMintingAllowance(address(cloneAddress), totalVestAmount);

        // deploy vesting contract with any wallet, setting forwarder, token and admin
        mVest = DssVestMintable(cloneFactory.createMintableVestingClone(salt, address(companyToken), companyAdminAddress, (totalVestAmount / vestDuration)));

        // grant minting allowance
        vm.prank(companyAdminAddress);
        companyToken.increaseMintingAllowance(address(mVest), totalVestAmount);
        
        // register domain separator with forwarder. Since the forwarder does not check the domain separator, we can use any string as domain name.
        vm.recordLogs();
        forwarder.registerDomainSeparator(string(abi.encodePacked(address(mVest))), "v1.0"); // simply uses address string as name
        Vm.Log[] memory logs = vm.getRecordedLogs();
        // the next line extracts the domain separator from the event emitted by the forwarder
        domainSeparator = logs[0].topics[1]; // internally, the forwarder calls this domainHash in registerDomainSeparator. But expects is as domainSeparator in execute().
        require(forwarder.domains(domainSeparator), "Registering failed");

        // register request type with forwarder. Since the forwarder does not check the request type, we can use any string as function name.
        vm.recordLogs();
        forwarder.registerRequestType("someFunctionName", "some function parameters");
        logs = vm.getRecordedLogs();
        // the next line extracts the request type from the event emitted by the forwarder
        requestType = logs[0].topics[1];
        require(forwarder.typeHashes(requestType), "Registering failed");
    }

    /**
     * @notice does the full setup and payout without meta tx
     * @dev Many local variables had to be removed to avoid stack too deep error
     */
    function testDemoEverythingLocal() public {

        uint startDate = block.timestamp;
        // create vest as company admin
        vm.prank(companyAdminAddress);
        uint256 id = mVest.create(employeeAddress, totalVestAmount, block.timestamp, vestDuration, vestCliff, companyAdminAddress);

        // accrued and claimable tokens can be checked at any time
        uint timeShift = 9 * 30 days;
        vm.warp(startDate + timeShift);
        uint unpaid = mVest.unpaid(id);
        assertEq(unpaid, 0, "unpaid is wrong: no tokens should be claimable yet");
        uint accrued = mVest.accrued(id);
        assertEq(accrued, totalVestAmount * timeShift / vestDuration, "accrued is wrong: some tokens should be accrued already");

        // claim tokens as employee
        timeShift = 2 * 365 days;
        vm.warp(startDate + timeShift);
        assertEq(companyToken.balanceOf(employeeAddress), 0, "employee already has tokens");
        vm.prank(employeeAddress);
        mVest.vest(id);
        assertEq(companyToken.balanceOf(employeeAddress), totalVestAmount * timeShift / vestDuration, "employee has received wrong token amount");
    }


    /**
     * @notice Create a new vest as companyAdmin using a meta tx that is sent by relayer
     */
    function testInitERC2771Local() public {
        // build request
        bytes memory payload = abi.encodeWithSelector(
            mVest.create.selector,
            employeeAddress, 
            totalVestAmount, 
            block.timestamp, 
            vestDuration, 
            0 days, 
            companyAdminAddress
        );

        IForwarder.ForwardRequest memory request = IForwarder.ForwardRequest({
            from: companyAdminAddress,
            to: address(mVest),
            value: 0,
            gas: 1000000,
            nonce: forwarder.getNonce(companyAdminAddress),
            data: payload,
            validUntil: block.timestamp + 1 hours // like this, the signature will expire after 1 hour. So the platform hotwallet can take some time to execute the transaction.
        });

        bytes memory suffixData = "0";


        // pack and hash request
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                domainSeparator,
                keccak256(
                    forwarder._getEncoded(request, requestType, suffixData)
                )
            )
        );

        // sign request.        
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            companyAdminPrivateKey,
            digest
        );
        bytes memory signature = abi.encodePacked(r, s, v); // https://docs.openzeppelin.com/contracts/2.x/utilities

        vm.prank(relayer);
        forwarder.execute(
            request,
            domainSeparator,
            requestType,
            suffixData,
            signature
        );
        (address usr, uint48 bgn, uint48 clf, uint48 fin, address mgr,, uint128 tot, uint128 rxd) = mVest.awards(1);
        assertEq(usr, employeeAddress);
        assertEq(uint256(bgn), block.timestamp);
        assertEq(uint256(clf), block.timestamp);
        assertEq(uint256(fin), block.timestamp + vestDuration);
        assertEq(uint256(tot), totalVestAmount);
        assertEq(uint256(rxd), 0);
        assertEq(mgr, companyAdminAddress);
    }

    /**
     * @notice Trigger payout as user using a meta tx that is sent by relayer
     * @dev Many local variables had to be removed to avoid stack too deep error
     */
    function testVestERC2771Local() public {
        vm.prank(companyAdminAddress);
        uint256 id = mVest.create(employeeAddress, totalVestAmount, block.timestamp, vestDuration, 0 days, companyAdminAddress);

        uint timeShift = 10 days;
        vm.warp(block.timestamp + timeShift);

        (address usr, uint48 bgn, uint48 clf, uint48 fin,,, uint128 tot, uint128 rxd) = mVest.awards(id);
        assertEq(usr, employeeAddress, "employeeAddress is wrong");
        assertEq(uint256(bgn), block.timestamp - timeShift, "bgn is wrong");
        assertEq(uint256(fin), block.timestamp + vestDuration - timeShift, "fin is wrong");
        assertEq(uint256(tot), totalVestAmount, "totalVestAmount is wrong");
        assertEq(uint256(rxd), 0, "rxd is wrong");
        assertEq(companyToken.balanceOf(employeeAddress), 0, "employeeAddress balance is wrong");

        IForwarder.ForwardRequest memory request = IForwarder.ForwardRequest({
            from: employeeAddress,
            to: address(mVest),
            value: 0,
            gas: 1000000,
            nonce: forwarder.getNonce(employeeAddress),
            data: abi.encodeWithSelector(
            bytes4(keccak256(bytes("vest(uint256)"))),
            id
        ),
            validUntil: block.timestamp + 1 hours // like this, the signature will expire after 1 hour. So the platform hotwallet can take some time to execute the transaction.
        });

        // sign request.        
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            employeePrivateKey,
            keccak256(abi.encodePacked(
                "\x19\x01",
                domainSeparator,
                keccak256(
                    forwarder._getEncoded(request, requestType, "0")
                )
            ))
        );

        vm.prank(relayer);
        forwarder.execute(
            request,
            domainSeparator,
            requestType,
            "0",
            abi.encodePacked(r, s, v)
        );

        (usr, bgn, clf, fin,,, tot, rxd) = mVest.awards(id);
        assertEq(usr, employeeAddress, "employeeAddress is wrong");
        assertEq(uint256(bgn), block.timestamp - timeShift, "bgn is wrong");
        assertEq(uint256(fin), block.timestamp + vestDuration - timeShift, "fin is wrong");
        assertEq(uint256(tot), totalVestAmount, "totalVestAmount is wrong");
        assertEq(uint256(rxd), totalVestAmount * timeShift / vestDuration, "rxd is wrong");
        assertEq(companyToken.balanceOf(employeeAddress), totalVestAmount * timeShift / vestDuration, "employeeAddress balance is wrong");
    }
}
