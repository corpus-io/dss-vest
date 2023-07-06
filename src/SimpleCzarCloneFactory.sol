// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import {DssVestCloneFactory} from "./DssVestCloneFactory.sol";
import {DssVestTransferrableCloneFactory} from "./DssVestTransferrableCloneFactory.sol";
import {SimpleCzar} from "./SimpleCzar.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";


contract SimpleCzarCloneFactory is DssVestCloneFactory {

    constructor(address _implementation) DssVestCloneFactory(_implementation) {}

    function createSimpleCzarClone(bytes32 salt, ERC20 gem, address dssVestTransferrable) external returns (address) {
        address clone = Clones.cloneDeterministic(implementation, salt);
        SimpleCzar(clone).initialize(gem, dssVestTransferrable);
        emit NewClone(clone);
        return clone;
    }
}