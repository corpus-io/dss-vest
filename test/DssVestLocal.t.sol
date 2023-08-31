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
import {DssVestMintable, DssVestTransferrable} from "../src/DssVest.sol";
import "./resources/ERC20MintableByAnyone.sol";

contract DssVestLocal is Test {
    // init forwarder
    Forwarder forwarder = new Forwarder();

    function setUp() public {
        vm.warp(60 * 365 days); // in local testing, the time would start at 1. This causes problems with the vesting contract. So we warp to 60 years.
    }

    function testFileWrongKeyLocal(address gem, uint256 value, string memory key) public {
        vm.assume(keccak256(abi.encodePacked(key)) != keccak256(abi.encodePacked("cap")));
        vm.assume(gem != address(0));
        DssVestMintable vest = new DssVestMintable(address(forwarder), gem, 0);
        vm.expectRevert("DssVest/file-unrecognized-param");
        vest.file("wrongKey", value);
    }

    function testRelyDenyLocal(address gem, address ward) public {
        vm.assume(gem != address(0));
        vm.assume(ward != address(0));
        vm.assume(ward != address(this));
        DssVestMintable vest = new DssVestMintable(address(forwarder), gem, 0);
        assertEq(vest.wards(ward), 0, "address is already a ward");
        vest.rely(ward);
        assertEq(vest.wards(ward), 1, "rely failed");
        vest.deny(ward);
        assertEq(vest.wards(ward), 0, "deny failed");
    }

    function testRequireAuthForCreateLocal(address noWard) public {
        DssVestMintable vest = new DssVestMintable(address(forwarder), address(1), 248829);
        vm.assume(vest.wards(noWard) == 0);
        vm.expectRevert("DssVest/not-authorized");
        vm.prank(noWard);
        vest.create(address(2), 1, 1, 1, 1, address(0));
    }

    function testCreateUnrestrictedMintableLocal(address _usr, address rando) public {
        vm.assume(_usr != address(0));
        vm.assume(rando != address(0));

        uint256 days_vest = 10**18;
        ERC20MintableByAnyone gem = new ERC20MintableByAnyone("gem", "GEM");

        DssVestMintable mVest = new DssVestMintable(address(forwarder), address(gem), 10**18);

        uint256 id = mVest.createUnrestricted(_usr, 100 * days_vest, block.timestamp, 100 days, 0 days, address(0));

        assertEq(mVest.res(id), 0, "Award is restricted");

        vm.warp(block.timestamp + 10 days);

        (address usr, uint48 bgn, uint48 clf, uint48 fin, address mgr,, uint128 tot, uint128 rxd) = mVest.awards(id);
        assertEq(usr, _usr);
        assertEq(uint256(bgn), block.timestamp - 10 days);
        assertEq(uint256(fin), block.timestamp + 90 days);
        assertEq(uint256(tot), 100 * days_vest);
        assertEq(uint256(rxd), 0);
        assertEq(gem.balanceOf(_usr), 0);

        // anyone can vest this unrestricted award
        vm.prank(rando);
        mVest.vest(id);
        (usr, bgn, clf, fin, mgr,, tot, rxd) = mVest.awards(id);
        assertEq(usr, _usr);
        assertEq(uint256(bgn), block.timestamp - 10 days);
        assertEq(uint256(fin), block.timestamp + 90 days);
        assertEq(uint256(tot), 100 * days_vest);
        assertEq(uint256(rxd), 10 * days_vest);
        assertEq(gem.balanceOf(_usr), 10 * days_vest);

        vm.warp(block.timestamp + 70 days);

        vm.prank(rando);
        mVest.vest(id, type(uint256).max);
        (usr, bgn, clf, fin, mgr,, tot, rxd) = mVest.awards(id);
        assertEq(usr, _usr);
        assertEq(uint256(bgn), block.timestamp - 80 days);
        assertEq(uint256(fin), block.timestamp + 20 days);
        assertEq(uint256(tot), 100 * days_vest);
        assertEq(uint256(rxd), 80 * days_vest);
        assertEq(gem.balanceOf(_usr), 80 * days_vest);
    }
}
