// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.0;

import "../interfaces/Xtokens.sol";
import "./ERC20Mock.sol";

contract xTokensMock is Xtokens{
    event xTokensTransfer(
        address currency,
        uint256 amount,
        uint64 weight
    );
    /// Transfer a token through XCM based on its currencyId
    ///
    /// @dev The token transfer burns/transfers the corresponding amount before sending
    /// @param currencyAddress The ERC20 address of the currency we want to transfer
    /// @param amount The amount of tokens we want to transfer
    /// @param destination The Multilocation to which we want to send the tokens
    /// @param destination The weight we want to buy in the destination chain
    /// @custom:selector b9f813ff
    function transfer(
        address currencyAddress,
        uint256 amount,
        Xtokens.Multilocation memory destination,
        uint64 weight
    ) external {
        ERC20Mock tokenMock = ERC20Mock(currencyAddress);
        tokenMock.burn(msg.sender, amount);
        emit xTokensTransfer(currencyAddress, amount, weight);
    }

    /// Transfer a token through XCM based on its currencyId specifying fee
    ///
    /// @dev The token transfer burns/transfers the corresponding amount before sending
    /// @param currencyAddress The ERC20 address of the currency we want to transfer
    /// @param amount The amount of tokens we want to transfer
    /// @param destination The Multilocation to which we want to send the tokens
    /// @param destination The weight we want to buy in the destination chain
    /// @custom:selector 3e506ef0
    function transferWithFee(
        address currencyAddress,
        uint256 amount,
        uint256 fee,
        Xtokens.Multilocation memory destination,
        uint64 weight
    ) external {}

    /// Transfer a token through XCM based on its MultiLocation
    ///
    /// @dev The token transfer burns/transfers the corresponding amount before sending
    /// @param asset The asset we want to transfer, defined by its multilocation.
    /// Currently only Concrete Fungible assets
    /// @param amount The amount of tokens we want to transfer
    /// @param destination The Multilocation to which we want to send the tokens
    /// @param destination The weight we want to buy in the destination chain
    /// @custom:selector b4f76f96
    function transferMultiasset(
        Xtokens.Multilocation memory asset,
        uint256 amount,
        Xtokens.Multilocation memory destination,
        uint64 weight
    ) external {}

    /// Transfer a token through XCM based on its MultiLocation specifying fee
    ///
    /// @dev The token transfer burns/transfers the corresponding amount before sending
    /// @param asset The asset we want to transfer, defined by its multilocation.
    /// Currently only Concrete Fungible assets
    /// @param amount The amount of tokens we want to transfer
    /// @param destination The Multilocation to which we want to send the tokens
    /// @param destination The weight we want to buy in the destination chain
    /// @custom:selector 150c016a
    function transferMultiassetWithFee(
        Xtokens.Multilocation memory asset,
        uint256 amount,
        uint256 fee,
        Xtokens.Multilocation memory destination,
        uint64 weight
    ) external {}

    /// Transfer several tokens at once through XCM based on its address specifying fee
    ///
    /// @dev The token transfer burns/transfers the corresponding amount before sending
    /// @param currencies The currencies we want to transfer, defined by their address and amount.
    /// @param feeItem Which of the currencies to be used as fee
    /// @param destination The Multilocation to which we want to send the tokens
    /// @param weight The weight we want to buy in the destination chain
    /// @custom:selector ab946323
    function transferMultiCurrencies(
        Xtokens.Currency[] memory currencies,
        uint32 feeItem,
        Xtokens.Multilocation memory destination,
        uint64 weight
    ) external {}

    /// Transfer several tokens at once through XCM based on its location specifying fee
    ///
    /// @dev The token transfer burns/transfers the corresponding amount before sending
    /// @param assets The assets we want to transfer, defined by their location and amount.
    /// @param feeItem Which of the currencies to be used as fee
    /// @param destination The Multilocation to which we want to send the tokens
    /// @param weight The weight we want to buy in the destination chain
    /// @custom:selector 797b45fd
    function transferMultiAssets(
        Xtokens.MultiAsset[] memory assets,
        uint32 feeItem,
        Xtokens.Multilocation memory destination,
        uint64 weight
    ) external {}
}
