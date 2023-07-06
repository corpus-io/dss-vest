// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.17;

import "../lib/forge-std/src/Test.sol";
import "@opengsn/contracts/src/forwarder/Forwarder.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";
import "../src/DssVest.sol";
import "../src/SimpleCzarCloneFactory.sol";
import "../src/DssVestTransferrableCloneFactory.sol";
import "./resources/ERC20MintableByAnyone.sol";


contract SimpleCzarCloneFactoryTest is Test {
    ERC20MintableByAnyone gem;
    SimpleCzar simpleCzarImplementation;
    SimpleCzarCloneFactory simpleCzarCloneFactory;
    DssVestTransferrable dssVestTransferrableImplementation;
    DssVestTransferrableCloneFactory dssVestTransferrableCloneFactory;

    address forwarder = address(0xf00d);


    function setUp() public {
        gem = new ERC20MintableByAnyone("Gem", "GEM");
        simpleCzarImplementation = new SimpleCzar(gem, address(1));
        simpleCzarCloneFactory = new SimpleCzarCloneFactory(address(simpleCzarImplementation));
        dssVestTransferrableImplementation = new DssVestTransferrable(forwarder, address(2), address(3));
        dssVestTransferrableCloneFactory = new DssVestTransferrableCloneFactory(address(dssVestTransferrableImplementation));
    }

    function testCreatesSimpleCzarCloneLocal(bytes32 salt, address fakeTransferrable) public {
        vm.assume(fakeTransferrable != address(0));

        // precalculate address
        address expectedCloneAddress = simpleCzarCloneFactory.predictCloneAddress(salt);

        // check fakeTransferrable allowance is 0
        assertEq(gem.allowance(expectedCloneAddress, fakeTransferrable), 0, "allowance should be 0");

        // create clone
        address clone = simpleCzarCloneFactory.createSimpleCzarClone(salt, gem, fakeTransferrable);
        assertEq(address(clone), expectedCloneAddress, "clone address does not match");
        assertEq(gem.allowance(address(clone), fakeTransferrable), type(uint256).max, "allowance not set");
    }

    function testCreatesTwoClonesLocal(bytes32 salt, address ward) public {


        // precalculate addresses
        address expectedSimpleCzarAddress = simpleCzarCloneFactory.predictCloneAddress(salt);
        address expectedDssVestTransferrableAddress = dssVestTransferrableCloneFactory.predictCloneAddress(salt);

        // check allowance is 0
        assertEq(gem.allowance(expectedSimpleCzarAddress, expectedDssVestTransferrableAddress), 0, "allowance should be 0");

        // create clones
        address dssVestTransferrableCloneAddress = simpleCzarCloneFactory.createSimpleCzarAndTransferrableClone(salt, gem, dssVestTransferrableCloneFactory, ward);
        DssVestTransferrable dssVestTransferrableClone = DssVestTransferrable(dssVestTransferrableCloneAddress);
        address simpleCzarCloneAddress = dssVestTransferrableClone.czar();
        assertEq(dssVestTransferrableCloneAddress, expectedDssVestTransferrableAddress, "transferrable clone address does not match");
        assertEq(simpleCzarCloneAddress, expectedSimpleCzarAddress, "simple czar clone address does not match");
        assertEq(gem.allowance(simpleCzarCloneAddress, dssVestTransferrableCloneAddress), type(uint256).max, "allowance not set");
    }


    
}
