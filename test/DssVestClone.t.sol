// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.17;

import "../lib/forge-std/src/Test.sol";
import "@opengsn/contracts/src/forwarder/Forwarder.sol";
import "@tokenize.it/contracts/contracts/Token.sol";
import "@tokenize.it/contracts/contracts/AllowList.sol";
import "@tokenize.it/contracts/contracts/FeeSettings.sol";
import "@openzeppelin/contracts/proxy/Proxy.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";

import "../src/DssVest.sol";
import "../src/DssVestMintableCloneFactory.sol";
import "../src/DssVestTransferrableCloneFactory.sol";
import "../src/DssVestSuckableCloneFactory.sol";

import "./resources/ERC20MintableByAnyone.sol";
import "./resources/TestHelper.sol";


contract DssVestCloneDemo is Test {
    event NewClone(address clone);

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

    TestHelper testHelpers = new TestHelper();

    DssVestMintableCloneFactory mintableFactory;
    DssVestTransferrableCloneFactory transferrableFactory;
    DssVestSuckableCloneFactory suckableFactory;

    uint tokenFeeDenominator = 100;
    uint paymentTokenFeeDenominator = 200;
    Token companyToken;
    FeeSettings feeSettings;
    AllowList allowList;

    uint8 v;
    bytes32 r;
    bytes32 s;

    uint256 days_vest = 10**18;

    function setUp() public {

        vm.warp(60 * 365 days); // in local testing, the time would start at 1. This causes problems with the vesting contract. So we warp to 60 years.

        // deploy tokenize.it platform
        vm.startPrank(platformAdminAddress);
        allowList = new AllowList();
        Fees memory fees = Fees(
            tokenFeeDenominator,
            paymentTokenFeeDenominator,
            paymentTokenFeeDenominator,
            0
        );

        feeSettings = new FeeSettings(fees, platformFeeCollector);
        vm.stopPrank();

        // set up clone factories
        DssVestMintable vestingImplementation = new DssVestMintable(address(forwarder), address(0x1), 0);
        mintableFactory = new DssVestMintableCloneFactory(address(vestingImplementation));
        DssVestTransferrable transferrableImplementation = new DssVestTransferrable(address(forwarder), address(0x1), address(0x2), 0);
        transferrableFactory = new DssVestTransferrableCloneFactory(address(transferrableImplementation));
    }

    function testMintableCloneCreationLocal(address newToken, address newAdmin, uint256 newCap, bytes32 salt) public {
        vm.assume(newToken != address(0x0));
        vm.assume(newAdmin != address(0x0));

        // Deploy proxy clone
        DssVestMintable mVest = DssVestMintable(mintableFactory.createMintableVestingClone(salt, newToken, newAdmin, newCap));

        console.log("factory address: ", address(mintableFactory));
        console.log("clone address: ", address(mVest));

        assertTrue(mVest.isTrustedForwarder(address(forwarder)), "Forwarder not set correctly");
        assertTrue(mVest.wards(newAdmin) == 1, "Admin not set correctly");
        assertTrue(address(mVest.gem()) == address(newToken), "Token not set correctly");
        assertTrue(mVest.cap() == newCap, "Cap not set correctly");

        // calling initializer again must revert
        vm.expectRevert("Initializable: contract is already initialized");
        mVest.initialize(newToken, newAdmin, newCap);
    }

    function testMintableCloneAddressPredictionLocal(address newToken, address newAdmin, bytes32 salt) public {
        vm.assume(newToken != address(0x0));
        vm.assume(newAdmin != address(0x0));

        address expectedAddress = mintableFactory.predictCloneAddress(salt);

        vm.expectEmit(true, true, true, true, address(mintableFactory));
        emit NewClone(expectedAddress); 

        // Deploy proxy clone
        DssVestMintable vest = DssVestMintable(mintableFactory.createMintableVestingClone(salt, newToken, newAdmin, 0));

        assertEq(address(vest), expectedAddress, "Address not as expected");

        // address prediction does not fail even if contract already exists
        address secondAddress = mintableFactory.predictCloneAddress(salt);
        assertEq(address(vest), secondAddress, "Address not as expected");

        // second clone creation with same salt must revert
        vm.expectRevert("ERC1167: create2 failed");
        mintableFactory.createMintableVestingClone(salt, newToken, newAdmin, 0);
    }

    function testTransferrableCloneCreationLocal(address czar, address gem, address ward, uint256 newCap) public {
        vm.assume(gem != address(0x0));
        vm.assume(ward != address(0x0));
        vm.assume(czar != address(0x0));

        bytes32 salt = bytes32(0);

        // Deploy proxy clone
        DssVestTransferrable vest = DssVestTransferrable(
            transferrableFactory.createTransferrableVestingClone(salt, czar, gem, ward, newCap));

        console.log("factory address: ", address(mintableFactory));
        console.log("clone address: ", address(vest));

        assertTrue(vest.isTrustedForwarder(address(forwarder)), "Forwarder not set correctly");
        assertTrue(vest.wards(ward) == 1, "ward not set correctly");
        assertTrue(address(vest.gem()) == gem, "gem not set correctly");
        assertTrue(address(vest.czar()) == czar, "czar not set correctly");
        assertTrue(vest.cap() == newCap, "cap not set correctly");

        // calling initializer again must revert
        vm.expectRevert("Initializable: contract is already initialized");
        vest.initialize(czar, gem, ward, newCap);
    }

    function testTransferrableAddressPredictionLocal(bytes32 salt, address czar, address gem, address ward, uint256 newCap) public {
        vm.assume(gem != address(0x0));
        vm.assume(ward != address(0x0));
        vm.assume(czar != address(0x0));

        address expectedAddress = transferrableFactory.predictCloneAddress(salt);

        vm.expectEmit(true, true, true, true, address(transferrableFactory));
        emit NewClone(expectedAddress); 

        // Deploy proxy clone
        DssVestTransferrable vest = DssVestTransferrable(
            transferrableFactory.createTransferrableVestingClone(salt, czar, gem, ward, newCap));

        assertEq(address(vest), expectedAddress, "Address not as expected");

        // address prediction does not fail even if contract already exists
        address secondAddress = transferrableFactory.predictCloneAddress(salt);
        assertEq(address(vest), secondAddress, "Address not as expected");

        // second clone creation with same salt must revert
        vm.expectRevert("ERC1167: create2 failed");
        transferrableFactory.createTransferrableVestingClone(salt, czar, gem, ward, newCap);
        
    }

    function testTransferrableCloneAsCzarLocal(bytes32 salt, address ward, address usr, uint128 amount, uint48 bgn, uint48 tau, uint48 eta, address mgr ) public {
        vm.assume(testHelpers.checkBounds(usr, amount, bgn, tau, eta, block.timestamp, address(forwarder)));
        vm.assume(ward != address(0x0));
        vm.assume(ward != address(forwarder));
        vm.assume(amount > 0);

        
        ERC20MintableByAnyone gem = new ERC20MintableByAnyone("Test Token", "TST");        

        // predict clone address
        address expectedAddress = transferrableFactory.predictCloneAddress(salt);

        // Deploy clone
        DssVestTransferrable vest = DssVestTransferrable(
            transferrableFactory.createTransferrableVestingClone(salt, expectedAddress, address(gem), ward, amount/tau));

        console.log("factory address: ", address(mintableFactory));
        console.log("clone address: ", address(vest));

        assertTrue(address(vest.czar()) == address(vest), "czar not set correctly");

        // mint amount to vest
        gem.mint(address(vest), amount);

        // create vesting plan
        vm.prank(ward);
        uint256 id = vest.create(usr, amount, bgn, tau, eta, mgr);

        // fast forward time
        vm.warp(bgn + tau);

        // make sure usr has no tokens before vesting
        assertEq(gem.balanceOf(usr), 0, "Balance of usr not 0");
        assertEq(gem.balanceOf(address(vest)), amount, "Balance of vesting contract not amount");

        vm.prank(usr);
        vest.vest(id);

        // check balance
        assertEq(gem.balanceOf(usr), amount, "Balance of usr not amount"); 
        assertEq(gem.balanceOf(address(vest)), 0, "Balance of vesting contract not 0");
    }

    /// @dev the suckable vesting contract needs on-chain infrastructure, thus it can not
    ///     be tested locally.
    function testSuckableCloneCreation(address ward, uint256 newCap) public {
        vm.assume(ward != address(0x0));

        address chainlog = 0xdA0Ab1e0017DEbCd72Be8599041a2aa3bA7e740F;
        DssVestSuckable suckableImplementation = new DssVestSuckable(address(forwarder), chainlog, newCap);
        suckableFactory = new DssVestSuckableCloneFactory(address(suckableImplementation));
        
        // Deploy proxy clone
        DssVestSuckable vest = DssVestSuckable(
            suckableFactory.createSuckableVestingClone(bytes32(0), chainlog, ward, newCap));

        assertTrue(vest.isTrustedForwarder(address(forwarder)), "Forwarder not set correctly");
        assertTrue(vest.wards(ward) == 1, "ward not set correctly");
        assertTrue(address(vest.chainlog()) == chainlog, "chainlog not set correctly");
        assertTrue(address(vest) != address(suckableFactory), "cloning failed");
        assertTrue(vest.cap() == newCap, "cap not set correctly");

        // calling initializer again must revert
        vm.expectRevert("Initializable: contract is already initialized");
        vest.initialize(chainlog, ward, newCap);
    }

    /// @dev the suckable vesting contract needs on-chain infrastructure, thus it can not
    ///     be tested locally.
    function testSuckableAddressPredictionCreation(bytes32 salt, address ward, uint256 newCap) public {
        vm.assume(ward != address(0x0));

        address chainlog = 0xdA0Ab1e0017DEbCd72Be8599041a2aa3bA7e740F;
        DssVestSuckable suckableImplementation = new DssVestSuckable(address(forwarder), chainlog, newCap);
        suckableFactory = new DssVestSuckableCloneFactory(address(suckableImplementation));

        address expectedAddress = suckableFactory.predictCloneAddress(salt);

        // check event. Address is not known yet, so we can't verify it.
        vm.expectEmit(true, true, true, true, address(suckableFactory));
        emit NewClone(expectedAddress); 
        
        // Deploy proxy clone
        DssVestSuckable vest = DssVestSuckable(
            suckableFactory.createSuckableVestingClone(salt, chainlog, ward, newCap));

        assertEq(address(vest), expectedAddress, "Address not as expected");

        // address prediction does not fail even if contract already exists
        address secondAddress = suckableFactory.predictCloneAddress(salt);
        assertEq(address(vest), secondAddress, "Address not as expected");

        // second clone creation with same salt must revert
        vm.expectRevert("ERC1167: create2 failed");
        suckableFactory.createSuckableVestingClone(salt, chainlog, ward, newCap);
    }
    
    function testReInitializationLocal(bytes32 salt, address newToken, address newAdmin, uint256 newCap) public {
        vm.assume(newToken != address(0x0));
        vm.assume(newAdmin != address(0x0));
        // Deploy proxy clone
        DssVestMintable mVest = DssVestMintable(mintableFactory.createMintableVestingClone(salt ,newToken, newAdmin, newCap));

        vm.expectRevert("Initializable: contract is already initialized");
        mVest.initialize(newAdmin, newAdmin, newCap);
    }

    /**
     * @notice Create a new vest as ward using a meta tx that is sent by relayer
     */
    function testCreateERC2771Local(bytes32 salt, address usrAddress) public {
        vm.assume(usrAddress != address(0x0));
        address adminAddress = vm.addr(companyAdminPrivateKey);

        Token newCompanyToken = new Token(
            address(forwarder),
            feeSettings,
            adminAddress,
            allowList,
            0, // set requirements 0 in order to keep this test simple
            "Company Token",
            "COMPT"
        );

        DssVestMintable localDssVest = DssVestMintable(mintableFactory.createMintableVestingClone(salt, address(newCompanyToken), adminAddress, 100));

        // register domain separator with forwarder. Since the forwarder does not check the domain separator, we can use any string as domain name.
        vm.recordLogs();
        forwarder.registerDomainSeparator(string(abi.encodePacked(address(localDssVest))), "v1.0"); // simply uses address string as name
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

        // build request
        bytes memory payload = abi.encodeWithSelector(
            localDssVest.create.selector,
            usrAddress, 
            100, 
            block.timestamp, 
            100 days, 
            0 days, 
            address(0x0)
        );

        IForwarder.ForwardRequest memory request = IForwarder.ForwardRequest({
            from: adminAddress,
            to: address(localDssVest),
            value: 0,
            gas: 1000000,
            nonce: forwarder.getNonce(adminAddress),
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
        (v, r, s) = vm.sign(
            companyAdminPrivateKey,
            digest
        );
        bytes memory signature = abi.encodePacked(r, s, v); // https://docs.openzeppelin.com/contracts/2.x/utilities

        require(address(this) != adminAddress, "sender must be admin");
        vm.prank(relayer);
        forwarder.execute(
            request,
            domainSeparator,
            requestType,
            suffixData,
            signature
        );

        console.log("signing address: ", request.from);
        (address usr, uint48 bgn,, uint48 fin,,, uint128 tot,) = localDssVest.awards(1);
        assertEq(usr, usrAddress);
        assertEq(uint256(bgn), block.timestamp);
        assertEq(uint256(fin), block.timestamp + 100 days);
        assertEq(uint256(tot), 100);
    }

    /**
     * @notice Use clone to vest tokens
     */
    function testCloneUseLocal(bytes32 salt, address localAdmin) public {
        vm.assume(localAdmin != address(0x0));
        vm.assume(localAdmin != address(forwarder));
        Token newCompanyToken = new Token(
            address(forwarder),
            feeSettings,
            localAdmin,
            allowList,
            0, // set requirements 0 in order to keep this test simple
            "Company Token",
            "COMPT"
        );

        DssVestMintable localDssVest = DssVestMintable(mintableFactory.createMintableVestingClone(salt, address(newCompanyToken), localAdmin, (totalVestAmount / vestDuration)));
        // grant minting allowance
        vm.prank(localAdmin);
        newCompanyToken.increaseMintingAllowance(address(localDssVest), totalVestAmount);

        // set up 
        uint startDate = block.timestamp;
        // create vest as company admin
        vm.prank(localAdmin);
        uint256 id = localDssVest.create(employeeAddress, totalVestAmount, block.timestamp, vestDuration, vestCliff, companyAdminAddress);

        // accrued and claimable tokens can be checked at any time
        uint timeShift = 9 * 30 days;
        vm.warp(startDate + timeShift);
        uint unpaid = localDssVest.unpaid(id);
        assertEq(unpaid, 0, "unpaid is wrong: no tokens should be claimable yet");
        uint accrued = localDssVest.accrued(id);
        assertEq(accrued, totalVestAmount * timeShift / vestDuration, "accrued is wrong: some tokens should be accrued already");

        // claim tokens as employee
        timeShift = 2 * 365 days;
        vm.warp(startDate + timeShift);
        assertEq(newCompanyToken.balanceOf(employeeAddress), 0, "employee already has tokens");
        vm.prank(employeeAddress);
        localDssVest.vest(id);
        assertEq(newCompanyToken.balanceOf(employeeAddress), totalVestAmount * timeShift / vestDuration, "employee has received wrong token amount");
    }

    function testNoWrongWardsLocal(bytes32 salt, address localCompanyAdmin, uint256 newCap) public {
        vm.assume(localCompanyAdmin != address(this));
        vm.assume(localCompanyAdmin != address(forwarder));
        vm.assume(localCompanyAdmin != address(0x0));
        vm.assume(localCompanyAdmin != platformAdminAddress);
        vm.assume(localCompanyAdmin != platformAdminAddress);
        vm.assume(localCompanyAdmin != address(mintableFactory));

        vm.startPrank(platformAdminAddress);
        Token localCompanyToken = new Token(
            address(forwarder),
            feeSettings,
            localCompanyAdmin,
            allowList,
            0, // set requirements 0 in order to keep this test simple
            "Company Token",
            "COMPT"
        );
        // Deploy clone
        DssVestMintable mVest = DssVestMintable(mintableFactory.createMintableVestingClone(salt, address(localCompanyToken), localCompanyAdmin, newCap));
        vm.stopPrank();

        console.log("factory address: ", address(mintableFactory));
        console.log("localCompanyAdmin: ", localCompanyAdmin);
        console.log("test account address: ", address(this));
        console.log("platformAdminAddress: ", platformAdminAddress);

        require(mVest.isTrustedForwarder(address(forwarder)), "Forwarder not trusted");
        require(address(mVest.gem()) == address(localCompanyToken), "Token not set");
        require(mVest.wards(localCompanyAdmin) == 1, "Company admin is not a ward");
        require(mVest.wards(address(mintableFactory)) == 0, "Factory is a ward");
        require(mVest.wards(platformAdminAddress) == 0, "Platform is a ward");
        require(mVest.wards(address(this)) == 0, "Test account is a ward");
        assertEq(mVest.cap(), newCap, "Cap is not set correctly");
    }

    /**
     * @notice does the full setup and payout without meta tx
     * @dev Many local variables had to be removed to avoid stack too deep error
     */
    function testDemoEverythingLocal(bytes32 salt, address localCompanyAdmin) public {

        vm.startPrank(platformAdminAddress);
        Token localCompanyToken = new Token(
            address(forwarder),
            feeSettings,
            localCompanyAdmin,
            allowList,
            0, // set requirements 0 in order to keep this test simple
            "Company Token",
            "COMPT"
        );

        // Deploy clone
        DssVestMintable mVest = DssVestMintable(mintableFactory.createMintableVestingClone(salt, address(localCompanyToken), localCompanyAdmin, (totalVestAmount / vestDuration)));
        vm.stopPrank();

        uint startDate = block.timestamp;
        // create vest as company admin
        vm.startPrank(localCompanyAdmin);
        uint256 id = mVest.create(employeeAddress, totalVestAmount, block.timestamp, vestDuration, vestCliff, localCompanyAdmin);
        // grant necessary minting allowance
        localCompanyToken.increaseMintingAllowance(address(mVest), totalVestAmount);
        vm.stopPrank();

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
        assertEq(localCompanyToken.balanceOf(employeeAddress), 0, "employee already has tokens");
        vm.prank(employeeAddress);
        mVest.vest(id);
        assertEq(localCompanyToken.balanceOf(employeeAddress), totalVestAmount * timeShift / vestDuration, "employee has received wrong token amount");
    }
    
    function testCreateUnrestrictedTransferrableLocal(address _usr, address rando, bytes32 salt) public {
        vm.assume(_usr != address(0));
        vm.assume(rando != address(0));

        ERC20MintableByAnyone gem = new ERC20MintableByAnyone("gem", "GEM");

        // predict clone address
        address expectedAddress = transferrableFactory.predictCloneAddress(salt);

        // Deploy clone
        DssVestTransferrable tVest = DssVestTransferrable(
            transferrableFactory.createTransferrableVestingClone(salt, expectedAddress, address(gem), address(this), 10**18));

        // mint necessary tokens
        gem.mint(address(tVest), 100 * days_vest);

        uint256 id = tVest.createUnrestricted(_usr, 100 * days_vest, block.timestamp, 100 days, 0 days, address(0));

        assertEq(tVest.res(id), 0, "Award is restricted");

        vm.warp(block.timestamp + 10 days);

        (address usr, uint48 bgn, uint48 clf, uint48 fin,,, uint128 tot, uint128 rxd) = tVest.awards(id);
        assertEq(usr, _usr);
        assertEq(uint256(bgn), block.timestamp - 10 days);
        assertEq(uint256(fin), block.timestamp + 90 days);
        assertEq(uint256(tot), 100 * days_vest);
        assertEq(uint256(rxd), 0);
        assertEq(gem.balanceOf(_usr), 0);

        // anyone can vest this unrestricted award
        vm.prank(rando);
        tVest.vest(id);
        (usr, bgn, clf, fin,,, tot, rxd) = tVest.awards(id);
        assertEq(usr, _usr);
        assertEq(uint256(bgn), block.timestamp - 10 days);
        assertEq(uint256(fin), block.timestamp + 90 days);
        assertEq(uint256(tot), 100 * days_vest);
        assertEq(uint256(rxd), 10 * days_vest);
        assertEq(gem.balanceOf(_usr), 10 * days_vest);

        vm.warp(block.timestamp + 70 days);

        vm.prank(rando);
        tVest.vest(id, type(uint256).max);
        (usr, bgn, clf, fin,,, tot, rxd) = tVest.awards(id);
        assertEq(usr, _usr);
        assertEq(uint256(bgn), block.timestamp - 80 days);
        assertEq(uint256(fin), block.timestamp + 20 days);
        assertEq(uint256(tot), 100 * days_vest);
        assertEq(uint256(rxd), 80 * days_vest);
        assertEq(gem.balanceOf(_usr), 80 * days_vest);
    }
    
}
