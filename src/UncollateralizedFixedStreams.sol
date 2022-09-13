// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC721} from "solmate/tokens/ERC721.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

error NOT_OWNER();

contract UncollateralizedFixedStreams is ERC721 {
    using SafeTransferLib for ERC20;

    struct Stream {
        address token;
        uint48 start;
        uint48 paidTo;
        address payer;
        uint96 amountPerSec;
    }

    uint256 public nextTokenId;

    event CreateStream(
        uint256 id,
        address from,
        address to,
        address token,
        uint96 amountPerSec,
        uint48 start
    );

    event CancelStream(uint256 id);

    event Withdraw(uint256 id, address token, address to, uint256 amount);

    event Deposit(uint256 id, address token, uint256 amount);

    mapping(uint256 => Stream) public streams;

    constructor() ERC721("Uncollateralized Fixed Stream", "UNCOLFXSTR") {
        nextTokenId = 1;
    }

    function createStream(
        address _to,
        address _token,
        uint96 _amountPerSec,
        uint48 _start
    ) external {
        uint256 id = nextTokenId;
        _safeMint(_to, id);
        streams[id] = Stream({
            token: _token,
            start: _start,
            paidTo: _start,
            payer: msg.sender,
            amountPerSec: _amountPerSec
        });

        unchecked {
            nextTokenId++;
        }

        emit CreateStream(id, msg.sender, _to, _token, _amountPerSec, _start);
    }

    function cancelStream(uint256 _id) external {
        Stream storage stream = streams[_id];
        if (msg.sender != stream.payer) revert NOT_OWNER();

        ERC20 token = ERC20(stream.token);
        address to = ownerOf(_id);

        uint256 delta = stream.paidTo - stream.start;
        uint256 toWithdraw;

        unchecked {
            toWithdraw =
                (stream.amountPerSec * delta) /
                (10**(20 - token.decimals()));
            streams[_id].start = stream.paidTo;
        }

        _burn(_id);
        token.safeTransfer(to, toWithdraw);

        emit Withdraw(_id, stream.token, to, toWithdraw);
        emit CancelStream(_id);
    }

    function deposit(uint256 _id, uint256 _amount) external {
        Stream storage stream = streams[_id];
        ERC20 token = ERC20(stream.token);
        uint256 toAdd;
        unchecked {
            toAdd =
                (_amount * (10**(20 - token.decimals()))) /
                stream.amountPerSec;
            streams[_id].paidTo += uint48(toAdd);
        }

        token.safeTransferFrom(msg.sender, address(this), _amount);

        emit Deposit(_id, stream.token, _amount);
    }

    function withdraw(uint256 _id) external {
        Stream storage stream = streams[_id];
        if (msg.sender != ownerOf(_id)) revert NOT_OWNER();

        ERC20 token = ERC20(stream.token);
        uint256 delta;
        uint256 toWithdraw;

        if (block.timestamp > stream.paidTo) {
            delta = stream.paidTo - stream.start;
            streams[_id].start = stream.paidTo;
        } else {
            delta = block.timestamp - stream.start;
            streams[_id].start = uint48(block.timestamp);
        }

        unchecked {
            toWithdraw =
                (stream.amountPerSec * delta) /
                (10**(20 - token.decimals()));
        }

        token.safeTransfer(msg.sender, toWithdraw);

        emit Withdraw(_id, stream.token, msg.sender, toWithdraw);
    }

    function withdrawable(uint256 _id)
        external
        view
        returns (uint256 withdrawableAmount, uint256 debt)
    {
        Stream storage stream = streams[_id];

        uint256 divisor = (10**(20 - ERC20(stream.token).decimals()));
        uint256 delta;

        if (block.timestamp > stream.paidTo) {
            delta = stream.paidTo - stream.start;
            debt =
                ((block.timestamp - stream.paidTo) * stream.amountPerSec) /
                divisor;
        } else {
            delta = block.timestamp - stream.start;
            debt = 0;
        }
        withdrawableAmount = (stream.amountPerSec * delta) / divisor;
    }

    function tokenURI(uint256 id)
        public
        view
        virtual
        override
        returns (string memory)
    {
        return "";
    }
}
