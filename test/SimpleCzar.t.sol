// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.17;

import "../lib/forge-std/src/Test.sol";
import "../src/SimpleCzar.sol";
import "./resources/ERC20MintableByAnyone.sol";


contract SimpleCzarTest is Test {
    ERC20MintableByAnyone gem;
    
    function setUp() public {
        gem = new ERC20MintableByAnyone("Gem", "GEM");
    }

    function testSetsUpAllowance(address fakeDssVestTransferrable) public {
        vm.assume(fakeDssVestTransferrable != address(0));
        SimpleCzar czar = new SimpleCzar(gem, address(fakeDssVestTransferrable));
        assertEq(gem.allowance(address(czar), address(fakeDssVestTransferrable)), type(uint256).max, "allowance not set");
    }

    function testDoesReleaseTokens(address fakeDssVestTransferrable, address receiver, uint256 amount, address thirdParty) public {
        vm.assume(receiver != address(0));
        vm.assume(fakeDssVestTransferrable != address(0));
        vm.assume(thirdParty != address(0));
        vm.assume(thirdParty != fakeDssVestTransferrable);
        vm.assume(amount > 0);
        SimpleCzar czar = new SimpleCzar(gem, address(fakeDssVestTransferrable));
        // supply the czar with tokens
        gem.mint(address(czar), amount);

        assertEq(gem.balanceOf(receiver), 0, "receiver already has tokens");

        // third party cannot release tokens
        vm.prank(thirdParty);
        vm.expectRevert();
        gem.transferFrom(address(czar), receiver, amount); 

        assertEq(gem.balanceOf(receiver), 0, "receiver should not have tokens yet");

        // release tokens
        vm.prank(fakeDssVestTransferrable);
        gem.transferFrom(address(czar), receiver, amount);

        assertEq(gem.balanceOf(receiver), amount, "receiver does not have right amount of tokens"); 

                  
    }
}
