// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity 0.8.17;

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