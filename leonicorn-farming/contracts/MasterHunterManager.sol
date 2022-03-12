// SPDX-License-Identifier:MIT

pragma solidity =0.6.12;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/IBEP20.sol";
import "./interfaces/IMasterHunter.sol";

contract MasterHunterManager is Ownable {
    IMasterHunter masterHunter;

    constructor(address _masterHunter) public {
        masterHunter = IMasterHunter(_masterHunter);
    }

    function updateMultiplier(uint256 multiplierNumber) external onlyOwner {
        masterHunter.updateMultiplier(multiplierNumber);
    }

    function add(
        uint256 _allocPoint,
        IBEP20 _lpToken,
        bool _withUpdate
    ) external onlyOwner {
        masterHunter.add(_allocPoint, _lpToken, _withUpdate);
    }

    // Update the given pool's LEON allocation point. Can only be called by the owner.
    function set(
        uint256 _pid,
        uint256 _allocPoint,
        bool _withUpdate
    ) external onlyOwner {
        masterHunter.set(_pid, _allocPoint, _withUpdate);
    }

    /**
     * Pause farming/staking. no more new staking/farming allowed, but withdraw/unstaking
     * is still possible
     */
    function pauseStaking() external onlyOwner {
        masterHunter.pauseStaking();
    }

    /**
     * Resume paused farming/staking, new staking/farmings are allowed
     */
    function resumeStaking() external onlyOwner {
        masterHunter.resumeStaking();
    }
}
