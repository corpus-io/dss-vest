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

import "../src/DssVest.sol";

contract DssVestMintable4Certora is DssVestMintable {

    constructor(address _forwarder, address _gem) DssVestMintable(_forwarder, _gem) {
    }

    function getMsgSender() public returns (address) {
        return _msgSender();
    }
}

// contract DssVestSuckable is DssVest {

//     uint256 internal constant RAY = 10**27;

//     ChainlogLike public immutable chainlog;
//     VatLike      public immutable vat;
//     DaiJoinLike  public immutable daiJoin;

//     /**
//         @dev This contract must be authorized to 'suck' on the vat
//         @param _chainlog The contract address of the MCD chainlog
//     */
//     constructor(address _forwarder, address _chainlog) DssVest(_forwarder) {
//         require(_chainlog != address(0), "DssVestSuckable/Invalid-chainlog-address");
//         ChainlogLike chainlog_ = chainlog = ChainlogLike(_chainlog);
//         VatLike vat_ = vat = VatLike(chainlog_.getAddress("MCD_VAT"));
//         DaiJoinLike daiJoin_ = daiJoin = DaiJoinLike(chainlog_.getAddress("MCD_JOIN_DAI"));

//         vat_.hope(address(daiJoin_));
//     }

//     /**
//         @dev Override pay to handle suck logic
//         @param _guy The recipient of the ERC-20 Dai
//         @param _amt The amount of Dai to send to the _guy [WAD]
//     */
//     function pay(address _guy, uint256 _amt) override internal {
//         require(vat.live() == 1, "DssVestSuckable/vat-not-live");
//         vat.suck(chainlog.getAddress("MCD_VOW"), address(this), mul(_amt, RAY));
//         daiJoin.exit(_guy, _amt);
//     }
// }

// /*
//     Transferrable token DssVest. Can be used to enable streaming payments of
//      any arbitrary token from an address (i.e. CU multisig) to individual
//      contributors.
// */
// contract DssVestTransferrable is DssVest {

//     address   public immutable czar;
//     TokenLike public immutable gem;

//     /**
//         @dev This contract must be approved for transfer of the gem on the czar
//         @param _czar The owner of the tokens to be distributed
//         @param _gem  The token to be distributed
//     */
//     constructor(address _forwarder, address _czar, address _gem) DssVest(_forwarder) {
//         require(_czar != address(0), "DssVestTransferrable/Invalid-distributor-address");
//         require(_gem  != address(0), "DssVestTransferrable/Invalid-token-address");
//         czar = _czar;
//         gem  = TokenLike(_gem);
//     }

//     /**
//         @dev Override pay to handle transfer logic
//         @param _guy The recipient of the ERC-20 Dai
//         @param _amt The amount of gem to send to the _guy (in native token units)
//     */
//     function pay(address _guy, uint256 _amt) override internal {
//         require(gem.transferFrom(czar, _guy, _amt), "DssVestTransferrable/failed-transfer");
//     }
// }
