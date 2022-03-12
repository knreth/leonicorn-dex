// SPDX-License-Identifier: MIT

pragma solidity =0.5.16;

import "./interfaces/ILeonicornFactoryV2.sol";
import "./interfaces/ILeonicornPairV2.sol";
import "./LeonicornPairV2.sol";

contract LeonicornFactoryV2 is ILeonicornFactoryV2 {
    bytes32 public constant INIT_CODE_PAIR_HASH =
        keccak256(abi.encodePacked(type(LeonicornPairV2).creationCode));

    address public feeTo;
    address public feeSetter;
    address private owner;

    mapping(address => mapping(address => address)) public getPair;
    address[] public allPairs;

    event OwnershipTransferred(
        address indexed previousOwner,
        address indexed newOwner
    );
    event PairCreated(
        address indexed token0,
        address indexed token1,
        address pair,
        uint256
    );

    constructor(address _feeSetter) public {
        feeSetter = _feeSetter;
        owner = msg.sender;
    }

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        require(msg.sender == owner, "Leonicorn: caller is not the owner");
        _;
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     */
    function transferOwnership(address newOwner) external onlyOwner {
        require(
            newOwner != address(0),
            "Leonicorn: new owner is the zero address"
        );
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }

    function allPairsLength() external view returns (uint256) {
        return allPairs.length;
    }

    function createPair(address tokenA, address tokenB)
        external
        returns (address pair)
    {
        require(tokenA != tokenB, "Leonicorn: IDENTICAL_ADDRESSES");
        (address token0, address token1) = tokenA < tokenB
            ? (tokenA, tokenB)
            : (tokenB, tokenA);
        require(token0 != address(0), "Leonicorn: ZERO_ADDRESS");
        require(
            getPair[token0][token1] == address(0),
            "Leonicorn: PAIR_EXISTS"
        ); // single check is sufficient
        bytes memory bytecode = type(LeonicornPairV2).creationCode;
        bytes32 salt = keccak256(abi.encodePacked(token0, token1));
        assembly {
            pair := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }
        ILeonicornPairV2(pair).initialize(token0, token1);
        getPair[token0][token1] = pair;
        getPair[token1][token0] = pair; // populate mapping in the reverse direction
        allPairs.push(pair);
        emit PairCreated(token0, token1, pair, allPairs.length);
    }

    function setFeeTo(address _feeTo) external {
        require(msg.sender == feeSetter, "Leonicorn: FORBIDDEN");
        feeTo = _feeTo;
    }

    function setFeeSetter(address _feeSetter) external {
        require(msg.sender == feeSetter, "Leonicorn: FORBIDDEN");
        feeSetter = _feeSetter;
    }

    function setTxFee(address pair, uint256 _txFee) external {
        require(msg.sender == feeSetter, "Leonicorn: FORBIDDEN");
        require(_txFee < 10000, "Leonicorn: Invalid tx fee");
        ILeonicornPairV2(pair).setTxFee(_txFee);
    }

    function pauseSwap(address pair) external onlyOwner {
        ILeonicornPairV2(pair).pauseSwap();
    }

    function resumeSwap(address pair) external onlyOwner {
        ILeonicornPairV2(pair).resumeSwap();
    }
}
