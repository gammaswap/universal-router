// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "../fixtures/TestBed.sol";
import "../../../contracts/test/TestUniversalRouter.sol";
import "../../../contracts/test/routes/TestAerodromeCL.sol";

contract AerodromeCLTest is TestBed {

    address owner;
    TestAerodromeCL route;

    function setUp() public {
        owner = vm.addr(1);
        initSetup(owner);

        route = new TestAerodromeCL(7, address(aeroCLFactory), address(weth));
    }
}
