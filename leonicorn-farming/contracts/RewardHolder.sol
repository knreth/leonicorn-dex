// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./LeonToken.sol";

contract RewardHolder is Ownable {
    /// Leon Token Address
    LeonToken public leon;
    bytes4 private constant SELECTOR =
        bytes4(keccak256(bytes("transfer(address,uint256)")));

    constructor(LeonToken _leon) public {
        leon = _leon;
    }

    function safeLeonTransfer(address _to, uint256 _amount) external onlyOwner {
        uint256 leonBal = leon.balanceOf(address(this));
        if (_amount > leonBal) {
            leon.transfer(_to, leonBal);
        } else {
            leon.transfer(_to, _amount);
        }
    }

    function leonTransferWithoutRevert(address to, uint256 value)
        external
        onlyOwner
        returns (bool)
    {
        (bool success, bytes memory data) = address(leon).call(
            abi.encodeWithSelector(SELECTOR, to, value)
        );
        return (success && (data.length == 0 || abi.decode(data, (bool))));
    }
}
