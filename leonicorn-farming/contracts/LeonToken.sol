// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "./BEP20.sol";

// LeonToken
contract LeonToken is BEP20('Leon Token', 'LEON') {
    /// @notice Creates `_amount` token to `_to`. Must only be called by the owner (MasterHunter).
    function mint(address _to, uint256 _amount) public onlyOwner {
        _mint(_to, _amount);
    }
}
