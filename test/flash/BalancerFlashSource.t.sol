// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../../contracts/flash/BalancerFlashSource.sol";
import "../mocks/FlashSourceReceiverTest.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract BalancerFlashSourceTest is Test {
    BalancerFlashSource public flashSource;
    FlashSourceReceiverTest public receiver;
    address public constant BALANCER_VAULT = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    // Test users
    address public alice = address(0x1);
    address public bob = address(0x2);

    function setUp() public {
        // Deploy contracts
        flashSource = new BalancerFlashSource(address(this)); // this contract acts as leverage manager
        receiver = new FlashSourceReceiverTest();
    }

    function test_constructor() public view {
        assertEq(flashSource.LEVERAGE_MANAGER(), address(this), "Incorrect leverage manager");
        assertEq(flashSource.source(), BALANCER_VAULT, "Incorrect Balancer vault");
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
        IERC20(WETH).approve(BALANCER_VAULT, flashAmount);
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

    function test_receiveFlashLoan_onlyBalancerVault() public {
        IERC20[] memory tokens = new IERC20[](1);
        uint256[] memory amounts = new uint256[](1);
        uint256[] memory feeAmounts = new uint256[](1);
        tokens[0] = IERC20(WETH);
        amounts[0] = 1 ether;
        feeAmounts[0] = 0;

        vm.startPrank(alice);
        vm.expectRevert(); // Callback verification failed
        flashSource.receiveFlashLoan(tokens, amounts, feeAmounts, "");
        vm.stopPrank();
    }

    function test_flash_DAI() public {
        uint256 flashAmount = 1000000 * 1e18; // 1M DAI

        // Ensure receiver has enough DAI to repay the flash loan
        deal(DAI, address(receiver), flashAmount);

        // Approve tokens for repayment
        vm.startPrank(address(receiver));
        IERC20(DAI).approve(BALANCER_VAULT, flashAmount);
        vm.stopPrank();

        // Execute flash loan
        bytes memory data = abi.encode(address(flashSource));
        flashSource.flash(DAI, flashAmount, address(receiver), data);

        // Try another flash loan - should work if workflow state was reset
        flashSource.flash(DAI, flashAmount, address(receiver), data);
    }

    function test_flash_USDC() public {
        uint256 flashAmount = 1000000 * 1e6; // 1M USDC

        // Ensure receiver has enough USDC to repay the flash loan
        deal(USDC, address(receiver), flashAmount);

        // Approve tokens for repayment
        vm.startPrank(address(receiver));
        IERC20(USDC).approve(BALANCER_VAULT, flashAmount);
        vm.stopPrank();

        // Execute flash loan
        bytes memory data = abi.encode(address(flashSource));
        flashSource.flash(USDC, flashAmount, address(receiver), data);

        // Try another flash loan - should work if workflow state was reset
        flashSource.flash(USDC, flashAmount, address(receiver), data);
    }

    function test_flash_WETH() public {
        uint256 flashAmount = 100 * 1e18; // 100 WETH

        // Ensure receiver has enough WETH to repay the flash loan
        deal(WETH, address(receiver), flashAmount);

        // Approve tokens for repayment
        vm.startPrank(address(receiver));
        IERC20(WETH).approve(BALANCER_VAULT, flashAmount);
        vm.stopPrank();

        // Execute flash loan
        bytes memory data = abi.encode(address(flashSource));
        flashSource.flash(WETH, flashAmount, address(receiver), data);

        // Try another flash loan - should work if workflow state was reset
        flashSource.flash(WETH, flashAmount, address(receiver), data);
    }

    function test_flash_invalidToken() public {
        address invalidToken = address(0x123); // Random address

        vm.expectRevert(); // Should revert when trying to flash loan an invalid token
        flashSource.flash(invalidToken, 1 ether, address(receiver), "");
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
