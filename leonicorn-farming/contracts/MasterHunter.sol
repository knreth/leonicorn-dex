// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "./libraries/SafeBEP20.sol";
import "./BEP20.sol";
import "./interfaces/IBEP20.sol";
import "./LeonToken.sol";
import "./RewardHolder.sol";

contract MasterHunter is Ownable {
    using SafeMath for uint256;
    using SafeBEP20 for IBEP20;

    // Info of each user.
    struct UserInfo {
        uint256 amount; // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
        //
        // We do some fancy math here. Basically, any point in time, the amount of LEONs
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.amount * pool.accLeonPerShare) - user.rewardDebt
        //
        // Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
        //   1. The pool's `accLeonPerShare` (and `lastRewardBlock`) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
    }

    // Info of each pool.
    struct PoolInfo {
        IBEP20 lpToken; // Address of LP token contract.
        uint256 allocPoint; // How many allocation points assigned to this pool. LEONs to distribute per block.
        uint256 lastRewardBlock; // Last block number that LEONs distribution occurs.
        uint256 accLeonPerShare; // Accumulated LEONs per share, times 1e12. See below.
    }

    // The LEON TOKEN!
    LeonToken public leon;
    // Temporary reward Holder!
    RewardHolder public rewardHolder;
    // LEON tokens created per block.
    uint256 public leonPerBlock;
    // Bonus muliplier for early leon makers.
    uint256 public BONUS_MULTIPLIER = 1;
  
    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;
    // The block number when LEON mining starts.
    uint256 public startBlock;
    /**
     * Staking state, cannot enter into staking/farming when it is set to true,
     * but unstaking/withdraw is allowed.
     */
    bool public stakingPaused = false;
    // Maaping for checking duplicate lpToken pool addition
    mapping(address => bool) private lpTokens;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(
        address indexed user,
        uint256 indexed pid,
        uint256 amount
    );

    constructor(
        LeonToken _leon,
        uint256 _leonPerBlock,
        uint256 _startBlock
    ) public {
        leon = _leon;
        leonPerBlock = _leonPerBlock;
        startBlock = _startBlock;

        /* Deploy reward holder contract */
        rewardHolder = new RewardHolder(_leon);

        // LEON staking pool
        poolInfo.push(
            PoolInfo({
                lpToken: _leon,
                allocPoint: 1000,
                lastRewardBlock: startBlock,
                accLeonPerShare: 0
            })
        );

        totalAllocPoint = 1000;
        lpTokens[address(_leon)] = true;
    }

    function updateMultiplier(uint256 multiplierNumber) external onlyOwner {
        BONUS_MULTIPLIER = multiplierNumber;
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    function add(
        uint256 _allocPoint,
        IBEP20 _lpToken,
        bool _withUpdate
    ) external onlyOwner {
        require(
            address(_lpToken) != address(0),
            "Leonicorn:  Invalid LP token address"
        );
        require(!lpTokens[address(_lpToken)], "Leonicorn: LP token exists");

        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardBlock = block.number > startBlock
            ? block.number
            : startBlock;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolInfo.push(
            PoolInfo({
                lpToken: _lpToken,
                allocPoint: _allocPoint,
                lastRewardBlock: lastRewardBlock,
                accLeonPerShare: 0
            })
        );
        updateStakingPool();
        lpTokens[address(_lpToken)] = true;
    }

    // Update the given pool's LEON allocation point. Can only be called by the owner.
    function set(
        uint256 _pid,
        uint256 _allocPoint,
        bool _withUpdate
    ) external onlyOwner {
        if (poolInfo[_pid].allocPoint != _allocPoint) {
            if (_withUpdate) {
                massUpdatePools();
            } else {
                updatePool(_pid);
            }

            totalAllocPoint = totalAllocPoint
                .sub(poolInfo[_pid].allocPoint)
                .add(_allocPoint);
            poolInfo[_pid].allocPoint = _allocPoint;
            updateStakingPool();
        }
    }

    function updateStakingPool() internal {
        uint256 length = poolInfo.length;
        uint256 points = 0;
        for (uint256 pid = 1; pid < length; ++pid) {
            points = points.add(poolInfo[pid].allocPoint);
        }
        if (points != 0) {
            points = points.div(3);
            totalAllocPoint = totalAllocPoint.sub(poolInfo[0].allocPoint).add(
                points
            );
            poolInfo[0].allocPoint = points;
        }
    }

    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(uint256 _from, uint256 _to)
        public
        view
        returns (uint256)
    {
        return _to.sub(_from).mul(BONUS_MULTIPLIER);
    }

    // View function to see pending LEONs on frontend.
    function pendingLeon(uint256 _pid, address _user)
        external
        view
        returns (uint256)
    {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accLeonPerShare = pool.accLeonPerShare;
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (block.number > pool.lastRewardBlock && lpSupply != 0) {
            uint256 multiplier = getMultiplier(
                pool.lastRewardBlock,
                block.number
            );
            uint256 leonReward = multiplier
                .mul(leonPerBlock)
                .mul(pool.allocPoint)
                .div(totalAllocPoint);
            accLeonPerShare = accLeonPerShare.add(
                leonReward.mul(1e12).div(lpSupply)
            );
        }
        return user.amount.mul(accLeonPerShare).div(1e12).sub(user.rewardDebt);
    }

    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (lpSupply == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
        uint256 leonReward = multiplier
            .mul(leonPerBlock)
            .mul(pool.allocPoint)
            .div(totalAllocPoint);
        leon.mint(address(rewardHolder), leonReward);
        pool.accLeonPerShare = pool.accLeonPerShare.add(
            leonReward.mul(1e12).div(lpSupply)
        );
        pool.lastRewardBlock = block.number;
    }

    function _deposit(uint256 _pid, uint256 _amount) internal {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);
        if (user.amount > 0) {
            uint256 pending = user
                .amount
                .mul(pool.accLeonPerShare)
                .div(1e12)
                .sub(user.rewardDebt);
            if (pending > 0) {
                safeLeonTransfer(msg.sender, pending);
            }
        }
        if (_amount > 0) {
            pool.lpToken.safeTransferFrom(
                address(msg.sender),
                address(this),
                _amount
            );
            user.amount = user.amount.add(_amount);
        }
        user.rewardDebt = user.amount.mul(pool.accLeonPerShare).div(1e12);
        emit Deposit(msg.sender, _pid, _amount);
    }

    // Deposit LP tokens to MasterHunter for LEON allocation.
    function deposit(uint256 _pid, uint256 _amount) external {
        require(!stakingPaused, "Leonicorn: Staking paused");
        require(_pid > 1, "deposit LEON/LEOS by staking");
        _deposit(_pid, _amount);
    }

    // Withdraw LP tokens from MasterHunter.
    function _withdraw(uint256 _pid, uint256 _amount) internal {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");
        updatePool(_pid);
        uint256 pending = user.amount.mul(pool.accLeonPerShare).div(1e12).sub(
            user.rewardDebt
        );
        if (pending > 0) {
            safeLeonTransfer(msg.sender, pending);
        }
        if (_amount > 0) {
            user.amount = user.amount.sub(_amount);
            pool.lpToken.safeTransfer(address(msg.sender), _amount);
        }
        user.rewardDebt = user.amount.mul(pool.accLeonPerShare).div(1e12);
        emit Withdraw(msg.sender, _pid, _amount);
    }

    // Withdraw LP tokens from MasterHunter.
    function withdraw(uint256 _pid, uint256 _amount) external {
        require(_pid > 1, "withdraw LEON/LEOS by unstaking");
        _withdraw(_pid, _amount);
    }

    // Stake LEON tokens to MasterHunter to earn LEONs
    function enterStaking(uint256 _amount) external {
        require(!stakingPaused, "Leonicorn: Staking paused");

        _deposit(0, _amount);
    }

    // Withdraw LEON tokens from STAKING.
    function leaveStaking(uint256 _amount) external {
        _withdraw(0, _amount);
    }

    // Stake LEOS tokens to MasterHunter to earn LEONs
    function enterLeosStaking(uint256 _amount) external {
        require(!stakingPaused, "Leonicorn: Staking paused");

        uint256 effectiveAmount;
        PoolInfo storage pool = poolInfo[1];
        UserInfo storage user = userInfo[1][msg.sender];
        updatePool(1);
        if (user.amount > 0) {
            uint256 pending = user
                .amount
                .mul(pool.accLeonPerShare)
                .div(1e12)
                .sub(user.rewardDebt);
            if (pending > 0) {
                safeLeonTransfer(msg.sender, pending);
            }
        }

        if (_amount > 0) {
            /* transfer from LEOS attracts 3% fee on each transfer, only _amount - 3% will be
             * transfered to recipient, user amount will be what we received. This fee may change.
             */

            uint256 lpSupply = pool.lpToken.balanceOf(address(this));
            pool.lpToken.safeTransferFrom(
                address(msg.sender),
                address(this),
                _amount
            );

            effectiveAmount = pool.lpToken.balanceOf(address(this)).sub(
                lpSupply
            );
            if (effectiveAmount > 0) {
                user.amount = user.amount.add(effectiveAmount);
            }
        }
        user.rewardDebt = user.amount.mul(pool.accLeonPerShare).div(1e12);

        emit Deposit(msg.sender, 1, effectiveAmount);
    }

    // Withdraw LEOS tokens from STAKING.
    function leaveLeosStaking(uint256 _amount) external {
        PoolInfo storage pool = poolInfo[1];
        UserInfo storage user = userInfo[1][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");
        updatePool(1);
        uint256 pending = user.amount.mul(pool.accLeonPerShare).div(1e12).sub(
            user.rewardDebt
        );
        if (pending > 0) {
            safeLeonTransfer(msg.sender, pending);
        }
        if (_amount > 0) {
            user.amount = user.amount.sub(_amount);
            pool.lpToken.safeTransfer(address(msg.sender), _amount);
        }
        user.rewardDebt = user.amount.mul(pool.accLeonPerShare).div(1e12);

        emit Withdraw(msg.sender, 1, _amount);
    }

    /**
     * Withdraw/Unstake without caring about rewards. EMERGENCY ONLY.
     * User's earned LEON rewards will be 'BURNED'.
     */
    function emergencyWithdraw(uint256 _pid) external {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        pool.lpToken.safeTransfer(address(msg.sender), user.amount);

        emit EmergencyWithdraw(msg.sender, _pid, user.amount);
        user.amount = 0;
        user.rewardDebt = 0;
    }

    /**
     * Safe Leon transfer function, just in case if rounding error causes
     * pool to not have enough LEONs.
     */
    function safeLeonTransfer(address _to, uint256 _amount) internal {
        rewardHolder.safeLeonTransfer(_to, _amount);
    }

    /**
     * Pause farming/staking. no more new staking/farming allowed, but withdraw/unstaking
     * is still possible
     */
    function pauseStaking() external onlyOwner {
        stakingPaused = true;
    }

    /**
     * Resume paused farming/staking, new staking/farmings are allowed
     */
    function resumeStaking() external onlyOwner {
        stakingPaused = false;
    }

    /**
     * Reclaim Leon token ownership from MasterHunter. Must be set through Governance
     * ONLY in EMERGENCY to safeguard LEONs.
     */
    function reclaimLeonOwnership() external onlyOwner {
        leon.transferOwnership(msg.sender);
    }
}
