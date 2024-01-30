// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.11;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {

    constructor() 
    ERC20("Mock", "Mock") {}

    function mint(address account_, uint256 amount_) external {
        _mint(account_, amount_);
    }

    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }

    function burnFrom(address account_, uint256 amount_) external {
        _burnFrom(account_, amount_);
    }

    function _burnFrom(address account_, uint256 amount_) internal {
        uint256 decreasedAllowance_ = allowance(account_, msg.sender) - amount_;

        _approve(account_, msg.sender, decreasedAllowance_);
        _burn(account_, amount_);
    }

    function decimals() public view virtual override returns (uint8) {
        return 9;
    }
}