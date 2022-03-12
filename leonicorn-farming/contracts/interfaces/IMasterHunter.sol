// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;
import "./IBEP20.sol";

interface IMasterHunter {
    function updateMultiplier(uint256 multiplierNumber) external;

    function add(
        uint256 _allocPoint,
        IBEP20 _lpToken,
        bool _withUpdate
    ) external;

    function set(
        uint256 _pid,
        uint256 _allocPoint,
        bool _withUpdate
    ) external;

    function deposit(uint256 _pid, uint256 _amount) external;

    function withdraw(uint256 _pid, uint256 _amount) external;

    function enterStaking(uint256 _amount) external;

    function leaveStaking(uint256 _amount) external;

    function enterLeosStaking(uint256 _amount) external;

    function leaveLeosStaking(uint256 _amount) external;

    function pendingLeon(uint256 _pid, address _user)
        external
        view
        returns (uint256);

    function userInfo(uint256 _pid, address _user)
        external
        view
        returns (uint256, uint256);

    function emergencyWithdraw(uint256 _pid) external;

    function pauseStaking() external;

    function resumeStaking() external;
}
