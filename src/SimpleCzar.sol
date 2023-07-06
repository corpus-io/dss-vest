// SPDX-License-Identifier: AGPL-3.0-or-later
//
// DssVest - Token vesting contract
//
// Copyright (C) 2021 Dai Foundation
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

pragma solidity 0.8.17;

import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";


/**
 * @title SimpleCzar
 * @author malteish
 * @notice This contract is used to hold tokens that can only be transferred by the DssVestTransferrable contract.
 */
contract SimpleCzar is Initializable {
    constructor(ERC20 _token, address _DssVestTransferrable) {
        initialize(_token, _DssVestTransferrable);
    }

    function initialize(ERC20 _token, address _DssVestTransferrable) public initializer {
        require(_token.approve(_DssVestTransferrable, type(uint256).max));
    }
}