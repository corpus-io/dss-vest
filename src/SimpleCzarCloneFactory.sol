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

    function createSimpleCzarAndTransferrableClone(bytes32 salt, ERC20 gem, DssVestTransferrableCloneFactory dssVestTransferrableCloneFactory, address ward) external returns (address) {
        address transferrableCloneAddress = dssVestTransferrableCloneFactory.predictCloneAddress(salt);
        
        // create and initialize the SimpleCzar clone
        address simpleCzarClone = Clones.cloneDeterministic(implementation, salt);
        SimpleCzar(simpleCzarClone).initialize(gem, transferrableCloneAddress);

        // create and initialize the DssVestTransferrable clone
        return dssVestTransferrableCloneFactory.createTransferrableVestingClone(salt, simpleCzarClone, address(gem), ward);
    }
}