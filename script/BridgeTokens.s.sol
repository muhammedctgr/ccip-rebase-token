// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {IRouterClient} from "@ccip/contracts/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {Client} from "@ccip/contracts/src/v0.8/ccip/libraries/Client.sol";

contract BridgeTokensScript is Script {
    function run(
        address receiverAddress,
        uint64 destinationChainSelector,
        uint256 amountToSend,
        address tokenToSendAddress,
        address linkTokenAddress,
        address routerAddress
    ) public {
        vm.startBroadcast();
        Client.EVMTokenAmount[]
            memory tokenAmounts = new Client.EVMTokenAmount[](1);
        tokenAmounts[0] = Client.EVMTokenAmount({
            token: tokenToSendAddress,
            amount: amountToSend
        });
        Client.EVM2AnyMessage message = Client.EVM2AnyMessage({
            receiver: abi.encode(receiverAddress),
            data: "",
            tokenAmounts: tokenAmounts,
            feeToken: linkTokenAddress,
            extraArgs: Client.EVM2AnyMessageExtraArgsV1({
                gasLimit: 200000,
                feeTokenAddress: address(0)
            })
        });
        IRouterClient(routerAddress).ccipSend(
            destinationChainSelector,
            message
        );
        vm.stopBroadcast();
    }
}
