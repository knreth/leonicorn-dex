// SPDX-License-Identifier: MIT
pragma solidity =0.6.12;

import "./interfaces/IBEP20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title LEON Staking
 */
contract LeonStaking is Ownable {
    using SafeMath for uint256;

    struct Stake {
        uint256 amount; //staked amount
        uint256 createdAt; // Timestamp of when stake was created
        uint256 rewardAmount; // Calculated reward amount, will be transfered to stake holder after plan expiry
        uint8 state; // state of the stake, 0 - FREE, 1 - ACTIVE, 2 - 'REMOVING'
        string plan;
    }

    struct Plan {
        string name; //The name of the plan, should be a single word in lowercase
        uint256 durationInDays; // The duration in days of the plan
        uint256 rewardPercentage; //The total reward percentage of the plan
        uint256 minimumStake; //The minimum amount a stakeholder can stake
        uint256 createdAt; // Timestamp of when plan was created
        uint256 usageCount; // How many stakes are in active on this plan
        uint256 stakedAmount;
        uint8 state; // State of the plan, 0 - Not Created, 1 - Active, 2 - Disabled
    }

    uint256 public constant MAX_NUM_OF_STAKES_PER_USER = 5;

    address public leonToken; /* LEON Token Contract Address */
    address public rewardAccount; //LEON account from which reward amount will be sent to Stake holders
    uint256 public totalStakedAmount; // Total staked amount, from all share holders
    uint256 public totalPendingRewardAmount; // Reward Amount pending to be rewarded to all stakeholders
    uint256 public totalRewardAmountClaimed; // Reward amount transfered to all stake holders
    bool public stakingPaused;

    //The stakes for each stakeholder.
    mapping(address => Stake[MAX_NUM_OF_STAKES_PER_USER]) internal stakes;

    //The plans
    mapping(string => Plan) internal plans;

    event PlanCreated(string name, uint256 duration, uint256 rewardPercentage);
    event PlanDeleted(string name);
    event ExcessRewardTransferred(address, uint256);
    event Staked(
        address sender,
        string plan,
        uint256 stakeAmount,
        uint256 duration,
        uint256 rewardAmount
    );
    event StakeRemoved(
        address sender,
        uint256 stakeIndex,
        uint256 stakeamount,
        uint256 rewardAmount
    );

    constructor(address _leonToken, address rewardsFrom) public {
        leonToken = _leonToken;
        rewardAccount = rewardsFrom;
    }

    /**
     * @notice A method for a stakeholder to create a stake.
     * @param _stakeAmount The size of the stake to be created.
     * @param _plan The type of stake to be created.
     */
    function enterStaking(uint256 _stakeAmount, string memory _plan)
        external
        returns (uint256 stakeIndex)
    {
        uint256 i;
        uint256 rewardAmount;

        Plan storage plan = plans[_plan];

        require(!stakingPaused, "LeonStaking: Staking Paused");
        /* plan must be valid and should not be disabled for further stakes */
        require(
            plan.state == 1,
            "LeonStaking: Invalid or disabled staking plan"
        );
        require(
            _stakeAmount >= plan.minimumStake,
            "LeonStaking: Stake is below minimum allowed stake"
        );

        // Transfer tokens from stake holders LEON account to this contract account
        IBEP20(leonToken).transferFrom(
            _msgSender(),
            address(this),
            _stakeAmount
        );

        if (plan.rewardPercentage > 0) {
            rewardAmount = (_stakeAmount.mul(plan.rewardPercentage).div(10000));

            IBEP20(leonToken).transferFrom(
                rewardAccount,
                address(this),
                rewardAmount
            );
        }
        /* A stack holder can stake upto MAX_NUM_OF_STAKES_PER_USER of stakes at any point of time */
        for (i = 0; i < MAX_NUM_OF_STAKES_PER_USER; i++)
            if (stakes[_msgSender()][i].state == 0) break;

        require(
            i < MAX_NUM_OF_STAKES_PER_USER,
            "LEONStacking: Reached maximum stakes per user"
        );

        Stake storage stake = stakes[_msgSender()][i];

        stake.amount = _stakeAmount;
        stake.plan = _plan;
        stake.rewardAmount = rewardAmount;
        stake.createdAt = block.timestamp;
        stake.state = 1; // Set to active statemul
        stakeIndex = i;

        totalStakedAmount = totalStakedAmount.add(_stakeAmount);
        totalPendingRewardAmount = totalPendingRewardAmount.add(
            stake.rewardAmount
        );

        plan.stakedAmount = plan.stakedAmount.add(_stakeAmount);

        /* Increase the usage count of this plan */
        plan.usageCount++;

        emit Staked(
            _msgSender(),
            _plan,
            _stakeAmount,
            plan.durationInDays,
            _stakeAmount.mul(plan.rewardPercentage).div(10000)
        );
    }

    function getStakesIndexes(address stakeHolder)
        external
        view
        returns (uint256[] memory stakesIndexes, uint256 numStakes)
    {
        uint256 i;
        uint256 j;

        for (i = 0; i < MAX_NUM_OF_STAKES_PER_USER; i++)
            if (stakes[stakeHolder][i].state == 1) numStakes++;

        if (numStakes > 0) {
            stakesIndexes = new uint256[](numStakes);

            for (i = 0; i < MAX_NUM_OF_STAKES_PER_USER; i++) {
                if (stakes[stakeHolder][i].state == 1) {
                    stakesIndexes[j] = i;
                    j++;
                }
            }
        }
    }

    function getStakeInfo(address stakeHolder, uint256 _stakeIndex)
        external
        view
        returns (
            uint256 stakeAmount,
            uint256 createdAt,
            uint256 rewardAmount,
            string memory plan
        )
    {
        if (
            _stakeIndex < MAX_NUM_OF_STAKES_PER_USER &&
            stakes[stakeHolder][_stakeIndex].state == 1
        ) {
            stakeAmount = stakes[stakeHolder][_stakeIndex].amount;
            createdAt = stakes[stakeHolder][_stakeIndex].createdAt;
            plan = stakes[stakeHolder][_stakeIndex].plan;
            rewardAmount = stakeAmount.mul(plans[plan].rewardPercentage).div(
                10000
            );
        }
    }

    function getStakedAmountByPlan(string memory _plan)
        external
        view
        onlyOwner
        returns (uint256)
    {
        if (plans[_plan].state > 0) return plans[_plan].stakedAmount;

        return 0;
    }

    /* Withdraw/Remove a stake */
    function withdrawStaking(uint256 _stakeIndex) external {
        uint256 amount;

        require(
            _stakeIndex < MAX_NUM_OF_STAKES_PER_USER,
            "LeonStaking: Invalid stake index"
        );

        Stake storage stake = stakes[_msgSender()][_stakeIndex];
        require(stake.state == 1, "LeonStaking: Stake is not active");
        require(
            _isExpired(stake.createdAt, plans[stake.plan].durationInDays),
            "LeonStaking: Stake Plan not expired yet"
        );

        // set the state to 'removing'
        stake.state = 2;

        /* transfer stake amount + rewared amount to the stake holder */
        amount = amount.add(stake.amount);
        amount = amount.add(stake.rewardAmount);

        IBEP20(leonToken).transfer(_msgSender(), amount);

        /* Update globals */
        totalStakedAmount = totalStakedAmount.sub(stake.amount);
        totalPendingRewardAmount = totalPendingRewardAmount.sub(
            stake.rewardAmount
        );
        totalRewardAmountClaimed = totalRewardAmountClaimed.add(
            stake.rewardAmount
        );

        plans[stake.plan].stakedAmount = plans[stake.plan].stakedAmount.sub(
            stake.amount
        );

        /* reduce plan active count */
        plans[stake.plan].usageCount--;

        emit StakeRemoved(
            _msgSender(),
            _stakeIndex,
            stake.amount,
            stake.amount.mul(plans[stake.plan].rewardPercentage).div(10000)
        );
        delete stakes[_msgSender()][_stakeIndex]; //Sets state to 0
    }

    /*
     */
    function transferExcessReward(address _to) external onlyOwner {
        uint256 excessAmount = IBEP20(leonToken).balanceOf(address(this));

        if (excessAmount > 0) {
            excessAmount = excessAmount.sub(
                totalStakedAmount.add(totalPendingRewardAmount)
            );
            IBEP20(leonToken).transfer(_to, excessAmount);
        }
        emit ExcessRewardTransferred(_to, excessAmount);
    }

    /*
     * @notice A method to pause staking. New stakes are not allowed once paused
     *
     */
    function pauseStaking() external onlyOwner returns (bool) {
        stakingPaused = true;
        return true;
    }

    /*
     * @notice A method to resume paused staking. New stakes are allowed once resumed
     *
     */
    function resumeStaking() external onlyOwner returns (bool) {
        stakingPaused = false;
        return true;
    }

    /*
     * @notice A method to update 'rewaredAccount'
     *
     */
    function updateRewardAccount(address _rewardAccount)
        external
        onlyOwner
        returns (bool)
    {
        require(
            _rewardAccount != address(0),
            "Invalid address for rewardAccount"
        );

        rewardAccount = _rewardAccount;
        return true;
    }

    /**
     * @notice A method for a contract owner to create a staking plan.
     * @param _name The name of the plan to be created.
     * @param _minimum_stake The minimum a stakeholder can stake.
     * @param _duration The duration in weeks of the plan to be created.
     * @param _reward_percentage The total reward percentage of the plan.
     *        Percentage should be in the degree of '100' (i.e multiply the required percent by 100)
     *        To set 10 percent, _reward_percentage should be 1000, to set 0.1 percent, it shoud be 10.
     */
    function createPlan(
        string memory _name,
        uint256 _minimum_stake,
        uint256 _duration,
        uint256 _reward_percentage
    ) external onlyOwner {
        require(_duration > 0, "LeonStaking: Duration in weeks can't be zero");
        require(_minimum_stake > 0, "LeonStaking: Minimum stake can't be zero");
        require(plans[_name].state == 0, "LeonStaking: Plan already exists");

        Plan storage plan = plans[_name];

        plan.name = _name;
        plan.minimumStake = _minimum_stake;
        plan.durationInDays = _duration;
        plan.rewardPercentage = _reward_percentage;
        plan.createdAt = block.timestamp;
        plan.state = 1;

        emit PlanCreated(plan.name, plan.durationInDays, plan.rewardPercentage);
    }

    function deletePlan(string memory _name) external onlyOwner {
        require(plans[_name].state > 0, "LeonStaking: Plan not found");
        require(plans[_name].usageCount == 0, "LeonStaking: Plan is in use");

        delete plans[_name];

        emit PlanDeleted(_name);
    }

    /*
     * @notice A method to disable a plan. No more new stakes will be added with this plan.
     * @param _name The plan name to disable
     */
    function disablePlan(string memory _name) external onlyOwner {
        require(plans[_name].state > 0, "LeonStaking: Plan doesn't exist");
        plans[_name].state = 2; //Disable
    }

    /**
     * @notice A method to retrieve the plan with the name.
     * @param _name The plan to retrieve
     */
    function getPlanInfo(string memory _name)
        external
        view
        returns (
            uint256 minimumStake,
            uint256 duration,
            uint256 rewardPercentage,
            uint256 usageCount,
            uint8 state
        )
    {
        Plan storage plan = plans[_name];

        if (plan.state > 0) {
            minimumStake = plan.minimumStake;
            duration = plan.durationInDays;
            rewardPercentage = plan.rewardPercentage;
            usageCount = plan.usageCount;
            state = plan.state;
        }
    }

    function _isExpired(uint256 _time, uint256 _duration)
        internal
        view
        returns (bool)
    {
        if (block.timestamp >= (_time + _duration * 1 days)) return true;
        else return false;
    }

    function getUserStakedAmount(address stakeHolder)
        external
        view
        returns (uint256 stakedAmount)
    {
        uint256 i;

        for (i = 0; i < MAX_NUM_OF_STAKES_PER_USER; i++)
            if (stakes[stakeHolder][i].state == 1) {
                stakedAmount = stakedAmount.add(stakes[stakeHolder][i].amount);
            }
    }
}
