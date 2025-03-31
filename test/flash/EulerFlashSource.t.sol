// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../../contracts/flash/EulerFlashSource.sol";
import "../mocks/FlashSourceReceiverTest.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract EulerFlashSourceTest is Test {
    EulerFlashSource public flashSource;
    FlashSourceReceiverTest public receiver;
    address public constant EULER_VAULT = 0xD8b27CF359b7D15710a5BE299AF6e7Bf904984C2; // Euler vault for WETH on ETH mainnet
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    // Test users
    address public alice = address(0x1);
    address public bob = address(0x2);

    function setUp() public {
        // Deploy contracts
        flashSource = new EulerFlashSource(address(this), EULER_VAULT); // this contract acts as leverage manager
        receiver = new FlashSourceReceiverTest();
    }

    function test_constructor() public view {
        assertEq(flashSource.LEVERAGE_MANAGER(), address(this), "Incorrect leverage manager");
        assertEq(flashSource.source(), EULER_VAULT, "Incorrect Euler vault");
    }

    function test_flash_onlyLeverageManager() public {
        vm.startPrank(alice);
        vm.expectRevert(bytes("OLM")); // From onlyLeverageManager modifier
        flashSource.flash(WETH, 1 ether, address(receiver), "");
        vm.stopPrank();
    }

    function test_flash_workflow() public {
        uint256 flashAmount = 1 ether;

        // Ensure receiver has enough WETH to repay the flash loan
        deal(WETH, address(receiver), flashAmount);

        // Approve tokens for repayment
        vm.startPrank(address(receiver));
        IERC20(WETH).approve(EULER_VAULT, flashAmount);
        vm.stopPrank();

        // First flash loan should work
        bytes memory data = abi.encode(address(flashSource));
        flashSource.flash(WETH, flashAmount, address(receiver), data);

        // Second flash loan should also work since workflow state is reset
        flashSource.flash(WETH, flashAmount, address(receiver), data);

        // Verify the receiver still has the expected balance
        // (it should have the original amount since it repaid both flash loans)
        assertEq(IERC20(WETH).balanceOf(address(receiver)), flashAmount, "Receiver balance incorrect after flash loans");
    }

    // function test_onFlashLoan_onlyEulerVault() public {
    //     vm.startPrank(alice);
    //     vm.expectRevert(bytes("CBV")); // Callback verification failed - only Euler vault can call
    //     flashSource.onFlashLoan("");
    //     vm.stopPrank();
    // }

    function test_flash_WETH() public {
        uint256 flashAmount = 100 * 1e18; // 100 WETH

        // Ensure receiver has enough WETH to repay the flash loan
        deal(WETH, address(receiver), flashAmount);

        // Approve tokens for repayment
        vm.startPrank(address(receiver));
        IERC20(WETH).approve(EULER_VAULT, flashAmount);
        vm.stopPrank();

        // Execute flash loan
        bytes memory data = abi.encode(address(flashSource));
        flashSource.flash(WETH, flashAmount, address(receiver), data);

        // Try another flash loan - should work if workflow state was reset
        flashSource.flash(WETH, flashAmount, address(receiver), data);
    }

    function test_flash_zeroAmount() public {
        vm.expectRevert(); // Should revert when trying to flash loan 0 tokens
        flashSource.flash(WETH, 0, address(receiver), "");
    }

    function test_flash_invalidRecipient() public {
        vm.expectRevert(); // Should revert when recipient is address(0)
        flashSource.flash(WETH, 1 ether, address(0), "");
    }
}
