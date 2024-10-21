// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { ZapInData, ZapOutData } from "contracts/libraries/ZapLib.sol";
import { SwapData } from "contracts/interfaces/ILiquidityConnector.sol";

struct DepositParams {
    address stakingContractAddress;
    address[] tokensIn;
    uint256[] amountsIn;
    ZapInData zapData;
    bytes extraData;
}

struct WithdrawParams {
    address stakingContractAddress;
    bytes extraData;
    ZapOutData zapData;
    address[] tokensOut;
}

struct HarvestParams {
    address stakingContractAddress;
    SwapData[] swaps;
    bytes extraData;
    address[] tokensOut;
}

struct CompoundParams {
    address claimContractAddress;
    bytes claimExtraData;
    address[] rewardTokens;
    ZapInData zapData;
    address depositContractAddress;
    bytes depositExtraData;
}
