// SPDX-License-Identifier: MIT
pragma solidity >=0.6.6;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/ILeonicornRouter02.sol";
import "./interfaces/ILeonicornFactoryV2.sol";
import "./libraries/TransferHelper.sol";
import "./interfaces/IWBNB.sol";
import "./interfaces/ILeonicornPairV2.sol";
import "./libraries/LeonicornLibrary.sol";

contract LeonicornRouterV2 is ILeonicornRouter02 {
    using SafeMath for uint256;

    address public immutable override factory;
    address public immutable override WBNB;
    address public txFeeSetter;
    address public treasury;
    uint256 public txFee = 10; // Transaction fee, 0.1%

    modifier ensure(uint256 deadline) {
        require(deadline >= block.timestamp, "LeonicornRouter: EXPIRED");
        _;
    }

    event UpdateTreasury(address _newTreasury);
    event UpdateTxFee(uint256 txFee);

    constructor(
        address _factory,
        address _WBNB,
        address _txFeeSetter,
        address _treasury
    ) public {
        factory = _factory;
        WBNB = _WBNB;
        txFeeSetter = _txFeeSetter;
        treasury = _treasury;
    }

    receive() external payable {
        assert(msg.sender == WBNB); // only accept BNB via fallback from the WBNB contract
    }

    // **** ADD LIQUIDITY ****
    function _addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin
    ) internal virtual returns (uint256 amountA, uint256 amountB) {
        // create the pair if it doesn't exist yet
        if (
            ILeonicornFactoryV2(factory).getPair(tokenA, tokenB) == address(0)
        ) {
            ILeonicornFactoryV2(factory).createPair(tokenA, tokenB);
        }
        (uint256 reserveA, uint256 reserveB) = LeonicornLibrary.getReserves(
            factory,
            tokenA,
            tokenB
        );
        if (reserveA == 0 && reserveB == 0) {
            (amountA, amountB) = (amountADesired, amountBDesired);
        } else {
            uint256 amountBOptimal = LeonicornLibrary.quote(
                amountADesired,
                reserveA,
                reserveB
            );
            if (amountBOptimal <= amountBDesired) {
                require(
                    amountBOptimal >= amountBMin,
                    "LeonicornRouter: INSUFFICIENT_B_AMOUNT"
                );
                (amountA, amountB) = (amountADesired, amountBOptimal);
            } else {
                uint256 amountAOptimal = LeonicornLibrary.quote(
                    amountBDesired,
                    reserveB,
                    reserveA
                );
                assert(amountAOptimal <= amountADesired);
                require(
                    amountAOptimal >= amountAMin,
                    "LeonicornRouter: INSUFFICIENT_A_AMOUNT"
                );
                (amountA, amountB) = (amountAOptimal, amountBDesired);
            }
        }
    }

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    )
        external
        virtual
        override
        ensure(deadline)
        returns (
            uint256 amountA,
            uint256 amountB,
            uint256 liquidity
        )
    {
        (amountA, amountB) = _addLiquidity(
            tokenA,
            tokenB,
            amountADesired,
            amountBDesired,
            amountAMin,
            amountBMin
        );
        address pair = LeonicornLibrary.pairFor(factory, tokenA, tokenB);
        TransferHelper.safeTransferFrom(tokenA, msg.sender, pair, amountA);
        TransferHelper.safeTransferFrom(tokenB, msg.sender, pair, amountB);
        liquidity = ILeonicornPairV2(pair).mint(to);
    }

    function getPair(address tokenA, address tokenB)
        external
        view
        returns (address pair)
    {
        pair = LeonicornLibrary.pairFor(factory, tokenA, tokenB);
    }

    function addLiquidityBNB(
        address token,
        uint256 amountTokenDesired,
        uint256 amountTokenMin,
        uint256 amountBNBMin,
        address to,
        uint256 deadline
    )
        external
        payable
        virtual
        override
        ensure(deadline)
        returns (
            uint256 amountToken,
            uint256 amountBNB,
            uint256 liquidity
        )
    {
        (amountToken, amountBNB) = _addLiquidity(
            token,
            WBNB,
            amountTokenDesired,
            msg.value,
            amountTokenMin,
            amountBNBMin
        );
        address pair = LeonicornLibrary.pairFor(factory, token, WBNB);
        TransferHelper.safeTransferFrom(token, msg.sender, pair, amountToken);
        IWBNB(WBNB).deposit{value: amountBNB}();
        assert(IWBNB(WBNB).transfer(pair, amountBNB));
        liquidity = ILeonicornPairV2(pair).mint(to);
        // refund dust bnb, if any
        if (msg.value > amountBNB)
            TransferHelper.safeTransferBNB(msg.sender, msg.value - amountBNB);
    }

    // **** REMOVE LIQUIDITY ****
    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    )
        public
        virtual
        override
        ensure(deadline)
        returns (uint256 amountA, uint256 amountB)
    {
        address pair = LeonicornLibrary.pairFor(factory, tokenA, tokenB);
        ILeonicornPairV2(pair).transferFrom(msg.sender, pair, liquidity); // send liquidity to pair
        (uint256 amount0, uint256 amount1) = ILeonicornPairV2(pair).burn(to);
        (address token0, ) = LeonicornLibrary.sortTokens(tokenA, tokenB);
        (amountA, amountB) = tokenA == token0
            ? (amount0, amount1)
            : (amount1, amount0);
        require(
            amountA >= amountAMin,
            "LeonicornRouter: INSUFFICIENT_A_AMOUNT"
        );
        require(
            amountB >= amountBMin,
            "LeonicornRouter: INSUFFICIENT_B_AMOUNT"
        );
    }

    function removeLiquidityBNB(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountBNBMin,
        address to,
        uint256 deadline
    )
        public
        virtual
        override
        ensure(deadline)
        returns (uint256 amountToken, uint256 amountBNB)
    {
        (amountToken, amountBNB) = removeLiquidity(
            token,
            WBNB,
            liquidity,
            amountTokenMin,
            amountBNBMin,
            address(this),
            deadline
        );
        TransferHelper.safeTransfer(token, to, amountToken);
        IWBNB(WBNB).withdraw(amountBNB);
        TransferHelper.safeTransferBNB(to, amountBNB);
    }

    function removeLiquidityWithPermit(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline,
        bool approveMax,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external virtual override returns (uint256 amountA, uint256 amountB) {
        address pair = LeonicornLibrary.pairFor(factory, tokenA, tokenB);
        uint256 value = approveMax ? uint256(-1) : liquidity;
        ILeonicornPairV2(pair).permit(
            msg.sender,
            address(this),
            value,
            deadline,
            v,
            r,
            s
        );
        (amountA, amountB) = removeLiquidity(
            tokenA,
            tokenB,
            liquidity,
            amountAMin,
            amountBMin,
            to,
            deadline
        );
    }

    function removeLiquidityBNBWithPermit(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountBNBMin,
        address to,
        uint256 deadline,
        bool approveMax,
        uint8 v,
        bytes32 r,
        bytes32 s
    )
        external
        virtual
        override
        returns (uint256 amountToken, uint256 amountBNB)
    {
        address pair = LeonicornLibrary.pairFor(factory, token, WBNB);
        uint256 value = approveMax ? uint256(-1) : liquidity;
        ILeonicornPairV2(pair).permit(
            msg.sender,
            address(this),
            value,
            deadline,
            v,
            r,
            s
        );
        (amountToken, amountBNB) = removeLiquidityBNB(
            token,
            liquidity,
            amountTokenMin,
            amountBNBMin,
            to,
            deadline
        );
    }

    // **** REMOVE LIQUIDITY (supporting fee-on-transfer tokens) ****
    function removeLiquidityBNBSupportingFeeOnTransferTokens(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountBNBMin,
        address to,
        uint256 deadline
    ) public virtual override ensure(deadline) returns (uint256 amountBNB) {
        (, amountBNB) = removeLiquidity(
            token,
            WBNB,
            liquidity,
            amountTokenMin,
            amountBNBMin,
            address(this),
            deadline
        );
        TransferHelper.safeTransfer(
            token,
            to,
            IERC20(token).balanceOf(address(this))
        );
        IWBNB(WBNB).withdraw(amountBNB);
        TransferHelper.safeTransferBNB(to, amountBNB);
    }

    function removeLiquidityBNBWithPermitSupportingFeeOnTransferTokens(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountBNBMin,
        address to,
        uint256 deadline,
        bool approveMax,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external virtual override returns (uint256 amountBNB) {
        address pair = LeonicornLibrary.pairFor(factory, token, WBNB);
        uint256 value = approveMax ? uint256(-1) : liquidity;
        ILeonicornPairV2(pair).permit(
            msg.sender,
            address(this),
            value,
            deadline,
            v,
            r,
            s
        );
        amountBNB = removeLiquidityBNBSupportingFeeOnTransferTokens(
            token,
            liquidity,
            amountTokenMin,
            amountBNBMin,
            to,
            deadline
        );
    }

    // **** SWAP ****
    // requires the initial amount to have already been sent to the first pair
    function _swap(
        uint256[] memory amounts,
        address[] memory path,
        address _to
    ) internal virtual {
        for (uint256 i; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]);
            (address token0, ) = LeonicornLibrary.sortTokens(input, output);
            uint256 amountOut = amounts[i + 1];
            (uint256 amount0Out, uint256 amount1Out) = input == token0
                ? (uint256(0), amountOut)
                : (amountOut, uint256(0));
            address to = i < path.length - 2
                ? LeonicornLibrary.pairFor(factory, output, path[i + 2])
                : _to;
            ILeonicornPairV2(LeonicornLibrary.pairFor(factory, input, output))
                .swap(amount0Out, amount1Out, to);
        }
    }

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    )
        external
        virtual
        override
        ensure(deadline)
        returns (uint256[] memory amounts)
    {
        amounts = LeonicornLibrary.getAmountsOut(
            factory,
            txFee,
            amountIn,
            path
        );
        require(
            amounts[amounts.length - 1] >= amountOutMin,
            "LeonicornRouter: INSUFFICIENT_OUTPUT_AMOUNT"
        );

        _receiveForTokens(path[0], path[1], amounts[0]);
        _swap(amounts, path, to);
    }

    function swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    )
        external
        virtual
        override
        ensure(deadline)
        returns (uint256[] memory amounts)
    {
        amounts = LeonicornLibrary.getAmountsIn(
            factory,
            txFee,
            amountOut,
            path
        );
        require(
            amounts[0] <= amountInMax,
            "LeonicornRouter: EXCESSIVE_INPUT_AMOUNT"
        );
        _receiveForTokens(path[0], path[1], amounts[0]);
        _swap(amounts, path, to);
    }

    function swapExactBNBForTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    )
        external
        payable
        virtual
        override
        ensure(deadline)
        returns (uint256[] memory amounts)
    {
        require(path[0] == WBNB, "LeonicornRouter: INVALID_PATH");
        amounts = LeonicornLibrary.getAmountsOut(
            factory,
            txFee,
            msg.value,
            path
        );
        require(
            amounts[amounts.length - 1] >= amountOutMin,
            "LeonicornRouter: INSUFFICIENT_OUTPUT_AMOUNT"
        );
        IWBNB(WBNB).deposit{value: amounts[0]}();
        _receiveForBNB(path[0], path[1], amounts[0]);
        _swap(amounts, path, to);
    }

    function swapTokensForExactBNB(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    )
        external
        virtual
        override
        ensure(deadline)
        returns (uint256[] memory amounts)
    {
        require(path[path.length - 1] == WBNB, "LeonicornRouter: INVALID_PATH");
        amounts = LeonicornLibrary.getAmountsIn(
            factory,
            txFee,
            amountOut,
            path
        );
        require(
            amounts[0] <= amountInMax,
            "LeonicornRouter: EXCESSIVE_INPUT_AMOUNT"
        );
        _receiveForTokens(path[0], path[1], amounts[0]);
        _swap(amounts, path, address(this));
        IWBNB(WBNB).withdraw(amounts[amounts.length - 1]);
        TransferHelper.safeTransferBNB(to, amounts[amounts.length - 1]);
    }

    function swapExactTokensForBNB(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    )
        external
        virtual
        override
        ensure(deadline)
        returns (uint256[] memory amounts)
    {
        require(path[path.length - 1] == WBNB, "LeonicornRouter: INVALID_PATH");
        amounts = LeonicornLibrary.getAmountsOut(
            factory,
            txFee,
            amountIn,
            path
        );
        require(
            amounts[amounts.length - 1] >= amountOutMin,
            "LeonicornRouter: INSUFFICIENT_OUTPUT_AMOUNT"
        );
        _receiveForTokens(path[0], path[1], amounts[0]);
        _swap(amounts, path, address(this));
        IWBNB(WBNB).withdraw(amounts[amounts.length - 1]);
        TransferHelper.safeTransferBNB(to, amounts[amounts.length - 1]);
    }

    function swapBNBForExactTokens(
        uint256 amountOut,
        address[] calldata path,
        address to,
        uint256 deadline
    )
        external
        payable
        virtual
        override
        ensure(deadline)
        returns (uint256[] memory amounts)
    {
        require(path[0] == WBNB, "LeonicornRouter: INVALID_PATH");
        amounts = LeonicornLibrary.getAmountsIn(
            factory,
            txFee,
            amountOut,
            path
        );
        require(
            amounts[0] <= msg.value,
            "LeonicornRouter: EXCESSIVE_INPUT_AMOUNT"
        );
        IWBNB(WBNB).deposit{value: amounts[0]}();
        _receiveForBNB(path[0], path[1], amounts[0]);
        _swap(amounts, path, to);
        // refund dust bnb, if any
        if (msg.value > amounts[0])
            TransferHelper.safeTransferBNB(msg.sender, msg.value - amounts[0]);
    }

    // **** SWAP (supporting fee-on-transfer tokens) ****
    // requires the initial amount to have already been sent to the first pair
    function _swapSupportingFeeOnTransferTokens(
        address[] memory path,
        address _to
    ) internal virtual {
        for (uint256 i; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]);
            (address token0, ) = LeonicornLibrary.sortTokens(input, output);
            ILeonicornPairV2 pair = ILeonicornPairV2(
                LeonicornLibrary.pairFor(factory, input, output)
            );
            uint256 amountInput;
            uint256 amountOutput;
            {
                // scope to avoid stack too deep errors
                (uint256 reserve0, uint256 reserve1, ) = pair.getReserves();
                (uint256 reserveInput, uint256 reserveOutput) = input == token0
                    ? (reserve0, reserve1)
                    : (reserve1, reserve0);
                amountInput = IERC20(input).balanceOf(address(pair)).sub(
                    reserveInput
                );
                amountOutput = LeonicornLibrary.getAmountOut(
                    txFee,
                    amountInput,
                    reserveInput,
                    reserveOutput
                );
            }
            (uint256 amount0Out, uint256 amount1Out) = input == token0
                ? (uint256(0), amountOutput)
                : (amountOutput, uint256(0));
            address to = i < path.length - 2
                ? LeonicornLibrary.pairFor(factory, output, path[i + 2])
                : _to;
            pair.swap(amount0Out, amount1Out, to);
        }
    }

    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external virtual override ensure(deadline) {
        TransferHelper.safeTransferFrom(
            path[0],
            msg.sender,
            LeonicornLibrary.pairFor(factory, path[0], path[1]),
            amountIn
        );
        uint256 balanceBefore = IERC20(path[path.length - 1]).balanceOf(to);
        _swapSupportingFeeOnTransferTokens(path, to);
        require(
            IERC20(path[path.length - 1]).balanceOf(to).sub(balanceBefore) >=
                amountOutMin,
            "LeonicornRouter: INSUFFICIENT_OUTPUT_AMOUNT"
        );
    }

    function swapExactBNBForTokensSupportingFeeOnTransferTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable virtual override ensure(deadline) {
        require(path[0] == WBNB, "LeonicornRouter: INVALID_PATH");
        uint256 amountIn = msg.value;
        IWBNB(WBNB).deposit{value: amountIn}();
        assert(
            IWBNB(WBNB).transfer(
                LeonicornLibrary.pairFor(factory, path[0], path[1]),
                amountIn
            )
        );
        uint256 balanceBefore = IERC20(path[path.length - 1]).balanceOf(to);
        _swapSupportingFeeOnTransferTokens(path, to);
        require(
            IERC20(path[path.length - 1]).balanceOf(to).sub(balanceBefore) >=
                amountOutMin,
            "LeonicornRouter: INSUFFICIENT_OUTPUT_AMOUNT"
        );
    }

    function swapExactTokensForBNBSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external virtual override ensure(deadline) {
        require(path[path.length - 1] == WBNB, "LeonicornRouter: INVALID_PATH");
        TransferHelper.safeTransferFrom(
            path[0],
            msg.sender,
            LeonicornLibrary.pairFor(factory, path[0], path[1]),
            amountIn
        );
        _swapSupportingFeeOnTransferTokens(path, address(this));
        uint256 amountOut = IERC20(WBNB).balanceOf(address(this));
        require(
            amountOut >= amountOutMin,
            "LeonicornRouter: INSUFFICIENT_OUTPUT_AMOUNT"
        );
        IWBNB(WBNB).withdraw(amountOut);
        TransferHelper.safeTransferBNB(to, amountOut);
    }

    // **** LIBRARY FUNCTIONS ****
    function quote(
        uint256 amountA,
        uint256 reserveA,
        uint256 reserveB
    ) external pure virtual override returns (uint256 amountB) {
        return LeonicornLibrary.quote(amountA, reserveA, reserveB);
    }

    function getAmountOut(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    ) external virtual override returns (uint256 amountOut) {
        return
            LeonicornLibrary.getAmountOut(
                txFee,
                amountIn,
                reserveIn,
                reserveOut
            );
    }

    function getAmountIn(
        uint256 amountOut,
        uint256 reserveIn,
        uint256 reserveOut
    ) external virtual override returns (uint256 amountIn) {
        return
            LeonicornLibrary.getAmountIn(
                txFee,
                amountOut,
                reserveIn,
                reserveOut
            );
    }

    function getAmountsOut(uint256 amountIn, address[] memory path)
        external
        view
        virtual
        override
        returns (uint256[] memory amounts)
    {
        return LeonicornLibrary.getAmountsOut(factory, txFee, amountIn, path);
    }

    function getAmountsIn(uint256 amountOut, address[] memory path)
        external
        view
        virtual
        override
        returns (uint256[] memory amounts)
    {
        return LeonicornLibrary.getAmountsIn(factory, txFee, amountOut, path);
    }

    function setTxFee(uint256 _txFee) external override {
        require(
            msg.sender == txFeeSetter,
            "Leonicorn: only txFeeSetter can set txFee"
        );
        txFee = _txFee;
        emit UpdateTxFee(_txFee);
    }

    function updateTreasury(address _newTreasury) external {
        require(
            msg.sender == treasury,
            "Leonicorn: only treasury can set new treasury"
        );
        treasury = _newTreasury;
        emit UpdateTreasury(_newTreasury);
    }

    function _transferToTreasury(address _token, uint256 _treasuryTxFee)
        internal
    {
        if (_treasuryTxFee > 0) {
            TransferHelper.safeTransferFrom(
                _token,
                msg.sender,
                treasury,
                _treasuryTxFee
            );
        }
    }

    function _receiveForTokens(
        address _tokenA,
        address _tokenB,
        uint256 _amount
    ) internal {
        address pair = LeonicornLibrary.pairFor(factory, _tokenA, _tokenB);
        uint256 _treasuryTxFee = _amount
            .sub(_amount.mul(10000).div(txFee.add(10000)))
            .mul(12)
            .div(100);

        TransferHelper.safeTransferFrom(
            _tokenA,
            msg.sender,
            pair,
            _amount.sub(_treasuryTxFee)
        );

        // Transfer a  portion of txFee to Treasury
        _transferToTreasury(_tokenA, _treasuryTxFee);
    }

    function _receiveForBNB(
        address _tokenA,
        address _tokenB,
        uint256 _amount
    ) internal {
        address pair = LeonicornLibrary.pairFor(factory, _tokenA, _tokenB);
        uint256 _treasuryTxFee = _amount
            .sub(_amount.mul(10000).div(txFee.add(10000)))
            .mul(12)
            .div(100);
        assert(IWBNB(WBNB).transfer(pair, _amount.sub(_treasuryTxFee)));

        // Transfer a  portion of txFee to Treasury
        _transferToTreasury(_tokenA, _treasuryTxFee);
    }
}
