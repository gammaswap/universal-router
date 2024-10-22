// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import '@openzeppelin/contracts/token/ERC20/ERC20.sol';

/// @dev Test purpose only!
contract Token is ERC20 {

    event  Deposit(address indexed dst, uint wad);
    event  Withdrawal(address indexed src, uint wad);

    string private _name;
    string private _symbol;
    uint8 private _decimals;

    constructor(string memory name_, string memory symbol_, uint8 decimals_) ERC20(name_, symbol_) {
        _decimals = decimals_;
    }

    function name() public view override returns (string memory) {
        return _name;
    }

    function symbol() public view override returns (string memory) {
        return _symbol;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function setName(string memory name_) external {
        _name = name_;
    }

    function setSymbol(string memory symbol_) external {
        _symbol = symbol_;
    }

    function setDecimals(uint8 decimals_) external {
        _decimals = decimals_;
    }

    function setMetaData(string memory name_, string memory symbol_, uint8 decimals_) external {
        _name = name_;
        _symbol = symbol_;
        _decimals = decimals_;
    }

    function mint(address account, uint256 amount) external {
        _mint(account, amount * 10 ** _decimals);
    }

    function deposit() public payable {
        _mint(msg.sender, msg.value);
        emit Deposit(msg.sender, msg.value);
    }

    function withdraw(uint256 wad) public {
        require(balanceOf(msg.sender) >= wad);
        _burn(msg.sender, wad);
        payable(msg.sender).transfer(wad);
        emit Withdrawal(msg.sender, wad);
    }
}
