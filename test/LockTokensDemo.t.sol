// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.17;

//import "ds-test/test.sol";
import "../lib/forge-std/src/Test.sol";
import "@opengsn/contracts/src/forwarder/Forwarder.sol";
import "@tokenize.it/contracts/contracts/Token.sol";
import "@tokenize.it/contracts/contracts/AllowList.sol";
import "@tokenize.it/contracts/contracts/FeeSettings.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../src/DssVest.sol";
import "../src/SimpleCzarCloneFactory.sol";
import "../src/DssVestTransferrableCloneFactory.sol";
import "./resources/ERC20MintableByAnyone.sol";


/**
 * @title LockTokensDemo
 * @author malteish
 * @notice Demonstration of how to use the DssVestTransferrable and SimpleCzar contracts in order to lock tokens up for a set duration.
 */
contract LockTokensDemo is Test {
    uint256 constant totalVestAmount = 42e18; // 42 tokens
    uint256 constant vestDuration = 1 * 365 days; // 1 year
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

    uint256 public constant beneficiaryPrivateKey =
        0x8da4ef21b864d2cc526dbdb2a120bd2874c36c9d0a1fb7f8c63d7f7a8b41de8f;
    address public beneficiary = vm.addr(beneficiaryPrivateKey); // = 0x63FaC9201494f0bd17B9892B9fae4d52fe3BD377;

    address public constant relayer =
        0xDFcEB49eD21aE199b33A76B726E2bea7A72127B0;

    address public constant platformFeeCollector =
        0x7109709eCfa91A80626Ff3989D68f67f5b1dD127;

    SimpleCzar simpleCzarImplementation;
    SimpleCzarCloneFactory simpleCzarCloneFactory;
    DssVestTransferrable dssVestTransferrableImplementation;
    DssVestTransferrableCloneFactory dssVestTransferrableCloneFactory;
    DssVestTransferrable tVest;

    uint tokenFeeDenominator = 100;
    uint paymentTokenFeeDenominator = 200;
    Token companyToken;

    function setUp() public {

        vm.warp(60 * 365 days); // in local testing, the time would start at 1. This causes problems with the vesting contract. So we warp to 60 years.

        // create logic contracts and clone factories
        // - Forwarder must be correct
        // - token address must implement approve() function, but will be replaced in clone
        ERC20MintableByAnyone someToken = new ERC20MintableByAnyone("Some Token", "SOME");
 
        simpleCzarImplementation = new SimpleCzar(someToken, address(1));
        simpleCzarCloneFactory = new SimpleCzarCloneFactory(address(simpleCzarImplementation));
        dssVestTransferrableImplementation = new DssVestTransferrable(address(forwarder), address(2), address(3));
        dssVestTransferrableCloneFactory = new DssVestTransferrableCloneFactory(address(dssVestTransferrableImplementation));

        // deploy tokenize.it platform 
        vm.startPrank(platformAdminAddress);
        AllowList allowList = new AllowList();
        Fees memory fees = Fees(
            tokenFeeDenominator,
            paymentTokenFeeDenominator,
            paymentTokenFeeDenominator,
            0
        );

        FeeSettings feeSettings = new FeeSettings(fees, platformFeeCollector);

        // deploy company token
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
        address simpleCzarCloneAddress = simpleCzarCloneFactory.predictCloneAddress(salt);
        address dssVestTransferrableCloneAddress = dssVestTransferrableCloneFactory.predictCloneAddress(salt);

        // important for real life: check if a contract already lives at this address. If that is the case, we cannot deploy a new clone with the same salt.
        // Address prediction function does not do this check!

        // deploy both contracts with any wallet, setting forwarder, token and admin
        tVest = DssVestTransferrable(simpleCzarCloneFactory.createSimpleCzarAndTransferrableClone(salt, companyToken, dssVestTransferrableCloneFactory, companyAdminAddress));

        // check addresses match
        assertEq(address(tVest), dssVestTransferrableCloneAddress, "Address prediction failed for DssVestTransferrableClone");
        assertEq(address(tVest.czar()), simpleCzarCloneAddress, "Address prediction failed for SimpleCzarClone");

        // configure vesting contract
        vm.prank(companyAdminAddress);
        tVest.file("cap", (totalVestAmount / vestDuration)); 

        // register domain separator with forwarder. Since the forwarder does not check the domain separator, we can use any string as domain name.
        vm.recordLogs();
        forwarder.registerDomainSeparator(string(abi.encodePacked(address(tVest))), "v1.0"); // simply uses address string as name
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
     * @notice tokens are minted to the simpleCzar contract, and can be paid out through the transferable vesting contract after the lockup period
     * @dev Many local variables had to be removed to avoid stack too deep error
     */
    function testDemoLockingTokensLocal() public {

        uint startDate = block.timestamp;

        // no tokens have been minted yet
        assertEq(companyToken.totalSupply(), 0, "wrong total supply");

        vm.startPrank(companyAdminAddress);
        // mint tokens to czar contract
        companyToken.increaseMintingAllowance(companyAdminAddress, totalVestAmount);
        companyToken.mint(address(tVest.czar()), totalVestAmount);
        // create vesting plan that allows withdrawal of tokens after vesting period
        uint256 id = tVest.create(beneficiary, totalVestAmount, startDate, vestDuration, vestCliff, companyAdminAddress);

        // tokens are in the czar contract
        assertEq(companyToken.balanceOf(address(tVest.czar())), totalVestAmount, "wrong amount of tokens in czar contract");

        // accrued and claimable tokens can be checked at any time
        uint timeShift = 9 * 30 days;
        vm.warp(startDate + timeShift);
        uint unpaid = tVest.unpaid(id);
        assertEq(unpaid, 0, "unpaid is wrong: no tokens should be claimable yet");
        uint accrued = tVest.accrued(id);
        assertEq(accrued, totalVestAmount * timeShift / vestDuration, "accrued is wrong: some tokens should be accrued already");

        // claim tokens as beneficiary
        timeShift = startDate + vestDuration;
        vm.warp(startDate + timeShift);
        assertEq(companyToken.balanceOf(beneficiary), 0, "beneficiary already has tokens");
        vm.prank(beneficiary);
        tVest.vest(id);
        assertEq(companyToken.balanceOf(beneficiary), totalVestAmount, "beneficiary has received wrong token amount");
    }


    // /**
    //  * @notice Create a new vest as companyAdmin using a meta tx that is sent by relayer
    //  */
    // function testInitERC2771Local() public {
    //     // build request
    //     bytes memory payload = abi.encodeWithSelector(
    //         tVest.create.selector,
    //         beneficiary, 
    //         totalVestAmount, 
    //         block.timestamp, 
    //         vestDuration, 
    //         0 days, 
    //         companyAdminAddress
    //     );

    //     IForwarder.ForwardRequest memory request = IForwarder.ForwardRequest({
    //         from: companyAdminAddress,
    //         to: address(tVest),
    //         value: 0,
    //         gas: 1000000,
    //         nonce: forwarder.getNonce(companyAdminAddress),
    //         data: payload,
    //         validUntil: block.timestamp + 1 hours // like this, the signature will expire after 1 hour. So the platform hotwallet can take some time to execute the transaction.
    //     });

    //     bytes memory suffixData = "0";


    //     // pack and hash request
    //     bytes32 digest = keccak256(
    //         abi.encodePacked(
    //             "\x19\x01",
    //             domainSeparator,
    //             keccak256(
    //                 forwarder._getEncoded(request, requestType, suffixData)
    //             )
    //         )
    //     );

    //     // sign request.        
    //     (uint8 v, bytes32 r, bytes32 s) = vm.sign(
    //         companyAdminPrivateKey,
    //         digest
    //     );
    //     bytes memory signature = abi.encodePacked(r, s, v); // https://docs.openzeppelin.com/contracts/2.x/utilities

    //     vm.prank(relayer);
    //     forwarder.execute(
    //         request,
    //         domainSeparator,
    //         requestType,
    //         suffixData,
    //         signature
    //     );
    //     (address usr, uint48 bgn, uint48 clf, uint48 fin, address mgr,, uint128 tot, uint128 rxd) = tVest.awards(1);
    //     assertEq(usr, beneficiary);
    //     assertEq(uint256(bgn), block.timestamp);
    //     assertEq(uint256(clf), block.timestamp);
    //     assertEq(uint256(fin), block.timestamp + vestDuration);
    //     assertEq(uint256(tot), totalVestAmount);
    //     assertEq(uint256(rxd), 0);
    //     assertEq(mgr, companyAdminAddress);
    // }

    // /**
    //  * @notice Trigger payout as user using a meta tx that is sent by relayer
    //  * @dev Many local variables had to be removed to avoid stack too deep error
    //  */
    // function testVestERC2771Local() public {
    //     vm.prank(companyAdminAddress);
    //     uint256 id = tVest.create(beneficiary, totalVestAmount, block.timestamp, vestDuration, 0 days, companyAdminAddress);

    //     uint timeShift = 10 days;
    //     vm.warp(block.timestamp + timeShift);

    //     (address usr, uint48 bgn, uint48 clf, uint48 fin,,, uint128 tot, uint128 rxd) = tVest.awards(id);
    //     assertEq(usr, beneficiary, "beneficiaryAddress is wrong");
    //     assertEq(uint256(bgn), block.timestamp - timeShift, "bgn is wrong");
    //     assertEq(uint256(fin), block.timestamp + vestDuration - timeShift, "fin is wrong");
    //     assertEq(uint256(tot), totalVestAmount, "totalVestAmount is wrong");
    //     assertEq(uint256(rxd), 0, "rxd is wrong");
    //     assertEq(companyToken.balanceOf(beneficiary), 0, "beneficiaryAddress balance is wrong");

    //     IForwarder.ForwardRequest memory request = IForwarder.ForwardRequest({
    //         from: beneficiary,
    //         to: address(tVest),
    //         value: 0,
    //         gas: 1000000,
    //         nonce: forwarder.getNonce(beneficiary),
    //         data: abi.encodeWithSelector(
    //         bytes4(keccak256(bytes("vest(uint256)"))),
    //         id
    //     ),
    //         validUntil: block.timestamp + 1 hours // like this, the signature will expire after 1 hour. So the platform hotwallet can take some time to execute the transaction.
    //     });

    //     // sign request.        
    //     (uint8 v, bytes32 r, bytes32 s) = vm.sign(
    //         beneficiaryPrivateKey,
    //         keccak256(abi.encodePacked(
    //             "\x19\x01",
    //             domainSeparator,
    //             keccak256(
    //                 forwarder._getEncoded(request, requestType, "0")
    //             )
    //         ))
    //     );

    //     vm.prank(relayer);
    //     forwarder.execute(
    //         request,
    //         domainSeparator,
    //         requestType,
    //         "0",
    //         abi.encodePacked(r, s, v)
    //     );

    //     (usr, bgn, clf, fin,,, tot, rxd) = tVest.awards(id);
    //     assertEq(usr, beneficiary, "beneficiaryAddress is wrong");
    //     assertEq(uint256(bgn), block.timestamp - timeShift, "bgn is wrong");
    //     assertEq(uint256(fin), block.timestamp + vestDuration - timeShift, "fin is wrong");
    //     assertEq(uint256(tot), totalVestAmount, "totalVestAmount is wrong");
    //     assertEq(uint256(rxd), totalVestAmount * timeShift / vestDuration, "rxd is wrong");
    //     assertEq(companyToken.balanceOf(beneficiary), totalVestAmount * timeShift / vestDuration, "beneficiaryAddress balance is wrong");
    // }
}
