// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../../contracts/flash/UniswapV3FlashSource.sol";
import "../mocks/FlashSourceReceiverTest.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

contract UniswapV3FlashSourceTest is Test {
    UniswapV3FlashSource public flashSource;
    FlashSourceReceiverTest public receiver;

    // USDC/DAI 0.01% pool
    address public constant POOL = 0x5777d92f208679DB4b9778590Fa3CAB3aC9e2168;
    address public constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    // Test users
    address public alice = address(0x1);
    address public bob = address(0x2);

    function setUp() public {
        // Deploy contracts
        flashSource = new UniswapV3FlashSource(POOL, address(this)); // this contract acts as leverage manager
        receiver = new FlashSourceReceiverTest();
    }

    function test_constructor() public view {
        assertEq(flashSource.LEVERAGE_MANAGER(), address(this), "Incorrect leverage manager");
        assertEq(flashSource.source(), POOL, "Incorrect Uniswap V3 pool");
    }

    function test_flash_onlyLeverageManager() public {
        vm.startPrank(alice);
        vm.expectRevert(bytes("OLM")); // From onlyLeverageManager modifier
        flashSource.flash(USDC, 1000e6, address(receiver), "");
        vm.stopPrank();
    }

    function test_flash_workflow_USDC() public {
        uint256 flashAmount = 1_000_000e6; // 1M USDC
        uint256 fee = (flashAmount * 1) / 10000; // 0.01% fee

        // Ensure receiver has enough USDC to repay the flash loan + fee
        deal(USDC, address(receiver), flashAmount + fee);

        // Approve tokens for repayment
        vm.startPrank(address(receiver));
        IERC20(USDC).approve(POOL, flashAmount + fee);
        vm.stopPrank();

        // First flash loan should work
        bytes memory data = abi.encode(address(flashSource));
        flashSource.flash(USDC, flashAmount, address(receiver), data);

        // Second flash loan should also work since workflow state is reset
        flashSource.flash(USDC, flashAmount, address(receiver), data);

        // Verify the receiver still has the expected balance
        // (it should have the original amount minus fees from both flash loans)
        assertEq(
            IERC20(USDC).balanceOf(address(receiver)),
            flashAmount + fee - (2 * fee),
            "Receiver balance incorrect after flash loans"
        );
    }

    function test_flash_workflow_DAI() public {
        uint256 flashAmount = 1_000_000e18; // 1M DAI
        uint256 fee = (flashAmount * 1) / 10000; // 0.01% fee

        // Ensure receiver has enough DAI to repay the flash loan + fee
        deal(DAI, address(receiver), flashAmount + fee);

        // Approve tokens for repayment
        vm.startPrank(address(receiver));
        IERC20(DAI).approve(POOL, flashAmount + fee);
        vm.stopPrank();

        // First flash loan should work
        bytes memory data = abi.encode(address(flashSource));
        flashSource.flash(DAI, flashAmount, address(receiver), data);

        // Second flash loan should also work since workflow state is reset
        flashSource.flash(DAI, flashAmount, address(receiver), data);

        // Verify the receiver still has the expected balance
        // (it should have the original amount minus fees from both flash loans)
        assertEq(
            IERC20(DAI).balanceOf(address(receiver)),
            flashAmount + fee - (2 * fee),
            "Receiver balance incorrect after flash loans"
        );
    }

    function test_uniswapV3FlashCallback_workflow() public {
        // Test that callback fails if workflow is not initialized
        IFlashLoanSource.FlashData memory fData = IFlashLoanSource.FlashData(address(receiver), USDC, 1000e6, "", 0);
        vm.startPrank(POOL);
        vm.expectRevert(bytes("F1")); // Workflow not initialized
        flashSource.uniswapV3FlashCallback(0, 0, abi.encode(fData));
        vm.stopPrank();
    }

    function test_uniswapV3FlashCallback_onlyPool() public {
        // Mock the pool to handle flash loan
        bytes4 flashSelector = bytes4(keccak256("flash(address,uint256,uint256,bytes)"));
        vm.mockCall(POOL, abi.encodeWithSelector(flashSelector), abi.encode());

        // Initialize workflow state by starting a flash loan
        uint256 flashAmount = 1000e6;
        bytes memory data = abi.encode(address(flashSource));
        vm.startPrank(address(this)); // as leverage manager
        flashSource.flash(USDC, flashAmount, address(receiver), data);
        vm.stopPrank();

        // Clear the mock to avoid interference
        vm.clearMockedCalls();

        // Test callback verification
        IFlashLoanSource.FlashData memory fData =
            IFlashLoanSource.FlashData(address(receiver), USDC, flashAmount, "", 0);
        vm.startPrank(alice);
        vm.expectRevert(bytes("CBV")); // Callback verification failed
        flashSource.uniswapV3FlashCallback(0, 0, abi.encode(fData));
        vm.stopPrank();
    }

    function test_flash_invalidToken() public {
        address invalidToken = address(0x123); // Random address

        vm.expectRevert(); // Should revert when trying to flash loan an invalid token
        flashSource.flash(invalidToken, 1 ether, address(receiver), "");
    }

    function test_flash_zeroAmount() public {
        vm.expectRevert(); // Should revert when trying to flash loan 0 tokens
        flashSource.flash(USDC, 0, address(receiver), "");
    }

    function test_flash_invalidRecipient() public {
        vm.expectRevert(); // Should revert when recipient is address(0)
        flashSource.flash(USDC, 1000e6, address(0), "");
    }
}
