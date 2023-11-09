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

    uint256 startOfTime = 60 * 365 days;

    // values for pause tests
    uint256 total = 100*10**18; // 100 tokens
    uint256 duration = 100; // 100 s
    uint256 eta = 10;
    uint256 pauseStart = 3 + startOfTime;
    uint256 pauseEnd = 33 + startOfTime;

    

    function setUp() public {
        vm.warp(startOfTime); // in local testing, the time would start at 1. This causes problems with the vesting contract. So we warp to 60 years.
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

    function testPauseBeforeCliffLocal(address _usr) public {
        vm.assume(_usr != address(0));

        ERC20MintableByAnyone gem = new ERC20MintableByAnyone("gem", "GEM");

        DssVestMintable mVest = new DssVestMintable(address(forwarder), address(gem), 10**18);

        uint256 id = mVest.create(_usr, total, startOfTime, duration, eta, address(0));

        vm.warp(startOfTime + 1);

        uint256 newId = mVest.pause(id, pauseStart, pauseEnd);

        // make sure old id is yanked by setting tot to 0 because it is inside cliff still
        (address usr, uint48 bgn, uint48 clf, uint48 fin,,, uint128 tot,) = mVest.awards(id);
        assertEq(usr, _usr, "user is not the same");
        assertEq(uint256(bgn), startOfTime, "start is wrong");
        assertEq(uint256(fin), pauseStart, "finish is wrong");
        assertEq(uint256(tot), 0, "total is wrong");

        // make sure new id has proper values
        (usr, bgn, clf, fin, ,, tot,) = mVest.awards(newId);
        assertEq(usr, _usr, "new user is not the same");
        assertEq(uint256(bgn), pauseEnd - 3, "new start is wrong"); // because 3 days of cliff had already passed 
        assertEq(uint256(clf), pauseEnd + 7, "new cliff is wrong"); // because 7 days of cliff remain
        assertEq(uint256(tot), total, "new total is wrong");
        assertEq(uint256(fin), pauseEnd + 97, "new end is wrong"); // because pause started after 3 days


        // go to end of vestings and claim all. It must match the total
        vm.warp(pauseEnd + 100);
        vm.startPrank(_usr);
        mVest.vest(newId, type(uint256).max);
        mVest.vest(id, type(uint256).max);

        assertEq(gem.balanceOf(_usr), total, "balance is wrong");
    }

function testPauseAfterCliffLocal(address _usr, uint256 pauseAfter, uint256 pauseDuration) public {
        vm.assume(_usr != address(0));
        pauseAfter = pauseAfter % 90 + 10; // range from 10 to 99
        pauseDuration = pauseDuration % (10 * 365 days) + 1;

        ERC20MintableByAnyone gem = new ERC20MintableByAnyone("gem", "GEM");

        DssVestMintable mVest = new DssVestMintable(address(forwarder), address(gem), 10**18);

        mVest.create(_usr, total, startOfTime, duration, eta, address(0)); // first id is 1

        vm.warp(startOfTime + 3);

        mVest.pause(1, startOfTime + pauseAfter, startOfTime + pauseAfter + pauseDuration); // new id is 2

        // make sure old id is yanked by setting tot to 0 because it is inside cliff still
        (address usr, uint48 bgn, uint48 clf, uint48 fin,,, uint128 tot,) = mVest.awards(1);
        assertEq(usr, _usr, "user is not the same");
        assertEq(uint256(bgn), startOfTime, "start is wrong");
        assertEq(uint256(fin), startOfTime + pauseAfter, "finish is wrong");
        assertTrue(uint256(tot) < total, "total is too much");
        assertTrue(uint256(tot) != 0, "total is 0");

        

        // make sure new id has proper values
        uint128 newTot;
        (usr, bgn, clf, fin,,, newTot,) = mVest.awards(2);
        assertEq(usr, _usr, "new user is not the same");
        assertEq(uint256(bgn), startOfTime + pauseAfter + pauseDuration, "new start is wrong"); // because 3 days of cliff had already passed 
        assertEq(uint256(clf), bgn, "new cliff is wrong"); // because 7 days of cliff remain
        assertEq(uint256(newTot), total - tot, "new total is wrong");
        assertEq(uint256(fin), startOfTime + pauseDuration + duration, "new end is wrong"); // because pause started after 3 days


        // go to end of vestings and claim all. It must match the total
        vm.warp(startOfTime + pauseAfter + pauseDuration + 1000 days);
        vm.startPrank(_usr);
        mVest.vest(2, type(uint256).max);
        mVest.vest(1, type(uint256).max);

        assertEq(gem.balanceOf(_usr), total, "balance is wrong");
    }

}
