// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {
    StrategyModule,
    SickleFactory,
    Sickle,
    ConnectorRegistry
} from "contracts/modules/StrategyModule.sol";
import { IFarmConnector } from "contracts/interfaces/IFarmConnector.sol";
import {
    DepositParams,
    HarvestParams,
    WithdrawParams,
    CompoundParams
} from "contracts/structs/FarmStrategyStructs.sol";
import { ZapLib } from "contracts/libraries/ZapLib.sol";
import { FeesLib } from "contracts/libraries/FeesLib.sol";
import { TransferLib } from "contracts/libraries/TransferLib.sol";
import { SickleRegistry } from "contracts/SickleRegistry.sol";
import { SwapLib } from "contracts/libraries/SwapLib.sol";

library FarmStrategyFees {
    bytes4 constant Deposit = bytes4(keccak256("FarmDepositFee"));
    bytes4 constant Harvest = bytes4(keccak256("FarmHarvestFee"));
    bytes4 constant Compound = bytes4(keccak256("FarmCompoundFee"));
    bytes4 constant Withdraw = bytes4(keccak256("FarmWithdrawFee"));
}

contract FarmStrategy is StrategyModule {
    struct Libraries {
        TransferLib transferLib;
        SwapLib swapLib;
        FeesLib feesLib;
        ZapLib zapLib;
    }

    error TokenOutRequired();

    ZapLib public immutable zapLib;
    SwapLib public immutable swapLib;
    TransferLib public immutable transferLib;
    FeesLib public immutable feesLib;

    address public immutable strategyAddress;

    constructor(
        SickleFactory factory,
        ConnectorRegistry connectorRegistry,
        Libraries memory libraries
    ) StrategyModule(factory, connectorRegistry) {
        zapLib = libraries.zapLib;
        swapLib = libraries.swapLib;
        transferLib = libraries.transferLib;
        feesLib = libraries.feesLib;
        strategyAddress = address(this);
    }

    function deposit(
        DepositParams calldata params,
        address[] memory sweepTokens,
        address approved,
        bytes32 referralCode
    ) public payable {
        if (params.tokensIn.length != params.amountsIn.length) {
            revert SickleRegistry.ArrayLengthMismatch();
        }
        if (params.tokensIn.length == 0) {
            revert TransferLib.TokenInRequired();
        }
        Sickle sickle = getOrDeploySickle(msg.sender, approved, referralCode);

        address[] memory targets = new address[](4);
        bytes[] memory data = new bytes[](4);

        targets[0] = address(transferLib);
        data[0] = abi.encodeCall(
            TransferLib.transferTokensFromUser,
            (
                params.tokensIn,
                params.amountsIn,
                strategyAddress,
                FarmStrategyFees.Deposit
            )
        );

        targets[1] = address(zapLib);
        data[1] = abi.encodeCall(ZapLib.zapIn, (params.zapData));

        targets[2] =
            connectorRegistry.connectorOf(params.stakingContractAddress);
        data[2] = abi.encodeCall(
            IFarmConnector.deposit,
            (
                params.stakingContractAddress,
                params.zapData.addLiquidityData.lpToken,
                params.extraData
            )
        );

        if (sweepTokens.length > 0) {
            targets[3] = address(transferLib);
            data[3] =
                abi.encodeCall(TransferLib.transferTokensToUser, (sweepTokens));
        }

        sickle.multicall{ value: msg.value }(targets, data);
    }

    function compound(
        CompoundParams calldata params,
        address[] memory sweepTokens
    ) external {
        Sickle sickle = getSickle(msg.sender);

        address[] memory targets = new address[](5);
        bytes[] memory data = new bytes[](5);

        address farmConnector =
            connectorRegistry.connectorOf(params.claimContractAddress);

        targets[0] = farmConnector;
        data[0] = abi.encodeCall(
            IFarmConnector.claim,
            (params.claimContractAddress, params.claimExtraData)
        );

        targets[1] = address(feesLib);
        data[1] = abi.encodeCall(
            FeesLib.chargeFees,
            (strategyAddress, FarmStrategyFees.Compound, params.rewardTokens)
        );

        targets[2] = address(zapLib);
        data[2] = abi.encodeCall(ZapLib.zapIn, (params.zapData));

        targets[3] = farmConnector;
        data[3] = abi.encodeCall(
            IFarmConnector.deposit,
            (
                params.depositContractAddress,
                params.zapData.addLiquidityData.lpToken,
                params.depositExtraData
            )
        );

        if (sweepTokens.length > 0) {
            targets[4] = address(transferLib);
            data[4] =
                abi.encodeCall(TransferLib.transferTokensToUser, (sweepTokens));
        }

        sickle.multicall(targets, data);
    }

    function withdraw(
        WithdrawParams calldata params,
        address[] memory sweepTokens
    ) public {
        if (params.tokensOut.length == 0) {
            revert TokenOutRequired();
        }

        Sickle sickle = getSickle(msg.sender);

        address[] memory targets = new address[](4);
        bytes[] memory data = new bytes[](4);

        address farmConnector =
            connectorRegistry.connectorOf(params.stakingContractAddress);
        targets[0] = farmConnector;
        data[0] = abi.encodeCall(
            IFarmConnector.withdraw,
            (
                params.stakingContractAddress,
                params.zapData.removeLiquidityData.lpAmountIn,
                params.extraData
            )
        );

        targets[1] = address(zapLib);
        data[1] = abi.encodeCall(ZapLib.zapOut, (params.zapData));

        targets[2] = address(feesLib);
        data[2] = abi.encodeCall(
            FeesLib.chargeFees,
            (strategyAddress, FarmStrategyFees.Withdraw, params.tokensOut)
        );

        if (sweepTokens.length > 0) {
            targets[3] = address(transferLib);
            data[3] =
                abi.encodeCall(TransferLib.transferTokensToUser, (sweepTokens));
        }

        sickle.multicall(targets, data);
    }

    function harvest(
        HarvestParams calldata params,
        address[] memory sweepTokens
    ) public {
        Sickle sickle = getSickle(msg.sender);

        address[] memory targets = new address[](4);
        bytes[] memory data = new bytes[](4);

        address farmConnector =
            connectorRegistry.connectorOf(params.stakingContractAddress);
        targets[0] = farmConnector;
        data[0] = abi.encodeCall(
            IFarmConnector.claim,
            (params.stakingContractAddress, params.extraData)
        );

        targets[1] = address(swapLib);
        data[1] = abi.encodeCall(SwapLib.swapMultiple, (params.swaps));
        targets[2] = address(feesLib);
        data[2] = abi.encodeCall(
            FeesLib.chargeFees,
            (strategyAddress, FarmStrategyFees.Harvest, params.tokensOut)
        );

        if (sweepTokens.length > 0) {
            targets[3] = address(transferLib);
            data[3] =
                abi.encodeCall(TransferLib.transferTokensToUser, (sweepTokens));
        }

        sickle.multicall(targets, data);
    }

    function exit(
        HarvestParams calldata harvestParams,
        WithdrawParams calldata withdrawParams,
        address[] memory sweepTokens
    ) external {
        // Sweep is handled by the withdraw
        harvest(harvestParams, new address[](0));
        withdraw(withdrawParams, sweepTokens);
    }
}
