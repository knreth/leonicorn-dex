// SPDX-License-Identifier: MIT
pragma solidity =0.5.16;

interface ILeonicornFactoryV2 {
    event PairCreated(
        address indexed token0,
        address indexed token1,
        address pair,
        uint256
    );

    function feeTo() external view returns (address);

    function feeSetter() external view returns (address);

    function getPair(address tokenA, address tokenB)
        external
        view
        returns (address pair);

    function allPairs(uint256) external view returns (address pair);

    function allPairsLength() external view returns (uint256);

    function createPair(address tokenA, address tokenB)
        external
        returns (address pair);

    function setFeeTo(address) external;

    function setFeeSetter(address) external;

    function setTxFee(address pair, uint256 _txFee) external;

    function pauseSwap(address pair) external;

    function resumeSwap(address pair) external;

    function INIT_CODE_PAIR_HASH() external view returns (bytes32);
}
