// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.17;

import "../lib/forge-std/src/Test.sol";
import "../src/SimpleCzar.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
   @dev This contract is used to test the DssVest contract. It is a ERC20 token that can be minted by anyone.
 */
contract ERC20MintableByAnyone is ERC20 {
    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) {}

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}

contract SimpleTransferrable {
    function transfer(address gem, address from, address to, uint256 amount) public virtual returns (bool) {}
}


contract SimpleCzarTest is Test {
    ERC20MintableByAnyone gem;
    SimpleTransferrable transferrable;
    
    function setUp() public {
        gem = new ERC20MintableByAnyone("Gem", "GEM");
        transferrable = new SimpleTransferrable();
    }

    function testSetsUpAllowance(address localTransferrable) public {
        vm.assume(localTransferrable != address(0));
        SimpleCzar czar = new SimpleCzar(gem, address(transferrable));
        assertEq(gem.allowance(address(czar), address(transferrable)), type(uint256).max, "allowance not set");
    }
}
