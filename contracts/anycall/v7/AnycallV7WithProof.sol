// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.10;

import "./AnycallV7Upgradeable.sol";

contract AnycallV7WithProof is AnyCallV7Upgradeable {
    mapping(address => bool) public isProofSigner;

    event LogAnyExecWithProof(
        bytes32 proofID,
        bytes32 txhash,
        uint256 fromChainID,
        uint256 nonce,
        uint256 logindex
    );

    event AddProofSigner(address signer);
    event RemoveProofSigner(address signer);

    struct ExecArgs {
        address to;
        bytes data;
        string appID;
        bytes extdata;
        uint256 logindex;
    }

    /// @notice exec with proof
    function anyExecWithProof(
        ExecArgs calldata _args,
        RequestContext calldata _ctx,
        bytes calldata _proof
    ) external virtual lock whenNotPaused chargeDestFee(_args.to, _ctx.flags) {
        require(_proof.length == 65, "wrong proof length");
        IAnycallConfig(config).checkExec(_args.appID, _ctx.from, _args.to);

        bytes32 uniqID = calcUniqID(
            _ctx.txhash,
            _ctx.from,
            _ctx.fromChainID,
            _ctx.nonce
        );
        require(!execCompleted[uniqID], "exec completed");
        execCompleted[uniqID] = true;

        bytes32 proofID;
        {
            ExecArgs memory args = _args; // fix Stack too deep
            RequestContext memory ctx = _ctx; // fix Stack too deep
            proofID = keccak256(
                abi.encode(
                    args.to,
                    args.data,
                    args.appID,
                    args.extdata,
                    args.logindex,
                    ctx.from,
                    ctx.fromChainID,
                    ctx.txhash,
                    ctx.nonce,
                    ctx.flags
                )
            );
            require(!execCompleted[proofID], "proof comsumed");
            execCompleted[proofID] = true;

            bytes32 r = bytes32(_proof[0:32]);
            bytes32 s = bytes32(_proof[32:64]);
            uint8 v = uint8(_proof[64]);
            address signer = ecrecover(proofID, v, r, s);
            require(signer != address(0) && isProofSigner[signer], "wrong proof");
        }

        bool success = _execute(_args.to, _args.data, _ctx, _args.extdata);

        if (!success) {
            if (_isSet(_ctx.flags, AnycallFlags.FLAG_ALLOW_FALLBACK)) {
                // Call the fallback on the originating chain
                nonce++;
                string memory appID = _args.appID; // fix Stack too deep
                emit LogAnyCall(
                    _args.to,
                    _ctx.from,
                    _args.data,
                    _ctx.fromChainID,
                    AnycallFlags.FLAG_EXEC_FALLBACK |
                        AnycallFlags.FLAG_PAY_FEE_ON_DEST, // pay fee on dest chain
                    appID,
                    nonce,
                    ""
                );
            } else {
                // Store retry record and emit a log
                bytes memory data = _args.data; // fix Stack too deep
                retryExecRecords[uniqID] = keccak256(
                    abi.encode(_args.to, data)
                );
                emit StoreRetryExecRecord(
                    _ctx.txhash,
                    _ctx.from,
                    _args.to,
                    _ctx.fromChainID,
                    _ctx.nonce,
                    data
                );
            }
        }

        emit LogAnyExecWithProof(
            proofID,
            _ctx.txhash,
            _ctx.fromChainID,
            _ctx.nonce,
            _args.logindex
        );
    }

    /// @notice add proof signers
    function addProofSigners(address[] calldata signers) external onlyMPC {
        address _signer;
        for (uint i = 0; i < signers.length; i++) {
            _signer = signers[i];
            require(_signer != address(0), "zero signer address");
            isProofSigner[_signer] = true;
            emit AddProofSigner(_signer);
        }
    }

    /// @notice remove proof signers
    function removeProofSigners(address[] calldata signers) external onlyMPC {
        address _signer;
        for (uint i = 0; i < signers.length; i++) {
            _signer = signers[i];
            isProofSigner[_signer] = false;
            emit RemoveProofSigner(_signer);
        }
    }
}
