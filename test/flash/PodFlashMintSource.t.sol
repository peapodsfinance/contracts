// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {PodHelperTest} from "../helpers/PodHelper.t.sol";
import {PodFlashMintSource} from "../../contracts/flash/PodFlashMintSource.sol";
import {IDecentralizedIndex} from "../../contracts/interfaces/IDecentralizedIndex.sol";
import {IFlashLoanRecipient} from "../../contracts/interfaces/IFlashLoanRecipient.sol";
import {MockFlashMintRecipient} from "../mocks/MockFlashMintRecipient.sol";
import {PEAS} from "../../contracts/PEAS.sol";
import {RewardsWhitelist} from "../../contracts/RewardsWhitelist.sol";
import {V3TwapUtilities} from "../../contracts/twaputils/V3TwapUtilities.sol";
import {UniswapDexAdapter} from "../../contracts/dex/UniswapDexAdapter.sol";

contract PodFlashMintSourceTest is PodHelperTest {
    address public pod;
    address public leverageManager;
    PodFlashMintSource public flashMintSource;
    MockFlashMintRecipient public flashMintRecipient;
    PEAS public peas;
    RewardsWhitelist public rewardsWhitelist;
    V3TwapUtilities public twapUtils;
    UniswapDexAdapter public dexAdapter;
    uint256 public bondAmt = 1e18;
    uint16 fee = 100; // 1%

    event FlashMint(address indexed executor, address indexed recipient, uint256 amount);

    function setUp() public override {
        super.setUp();

        // Setup contracts
        peas = PEAS(0x02f92800F57BCD74066F5709F1Daa1A4302Df875);
        twapUtils = new V3TwapUtilities();
        rewardsWhitelist = new RewardsWhitelist();
        dexAdapter = new UniswapDexAdapter(
            twapUtils,
            0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D, // Uniswap V2 Router
            0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45, // Uniswap SwapRouter02
            false
        );

        // Setup test addresses
        leverageManager = address(0x123); // Mock leverage manager address

        // Create a new pod using PodHelperTest._createPod()
        IDecentralizedIndex.Config memory _c;
        IDecentralizedIndex.Fees memory _f;
        _f.bond = fee;
        _f.debond = fee;
        address[] memory _t = new address[](1);
        _t[0] = address(peas);
        uint256[] memory _w = new uint256[](1);
        _w[0] = 100;
        pod = _createPod(
            "Test",
            "pTEST",
            _c,
            _f,
            _t,
            _w,
            address(0),
            false,
            abi.encode(
                0x6B175474E89094C44Da98b954EedeAC495271d0F, // DAI as paired token
                address(peas),
                0x6B175474E89094C44Da98b954EedeAC495271d0F,
                0x7d544DD34ABbE24C8832db27820Ff53C151e949b,
                address(rewardsWhitelist),
                0x024ff47D552cB222b265D68C7aeB26E586D5229D,
                dexAdapter
            )
        );

        // Deploy flash mint source and recipient
        flashMintSource = new PodFlashMintSource(pod, leverageManager);
        flashMintRecipient = new MockFlashMintRecipient();
        flashMintRecipient.setShouldUseShource(true);

        // Deal some PEAS tokens and bond to get pod tokens
        deal(address(peas), address(this), bondAmt * 100);
        IERC20(peas).approve(address(pod), type(uint256).max);
        IDecentralizedIndex(pod).bond(address(peas), bondAmt * 10, 0);

        // Setup approvals for flash minting
        IERC20(pod).approve(address(flashMintSource), type(uint256).max);
        IERC20(pod).approve(address(pod), type(uint256).max);

        // Setup flash mint recipient
        vm.startPrank(address(flashMintRecipient));
        IERC20(pod).approve(address(pod), type(uint256).max);
        vm.stopPrank();

        // Setup leverage manager with pod tokens
        deal(address(peas), leverageManager, bondAmt * 100);
        vm.startPrank(leverageManager);
        IERC20(peas).approve(address(pod), type(uint256).max);
        IDecentralizedIndex(pod).bond(address(peas), bondAmt * 10, 0);
        IERC20(pod).approve(address(pod), type(uint256).max);
        IERC20(pod).approve(address(flashMintSource), type(uint256).max);
        vm.stopPrank();
    }

    function test_constructor() public view {
        assertEq(flashMintSource.source(), pod, "Source should be pod");
        assertEq(flashMintSource.LEVERAGE_MANAGER(), leverageManager, "Leverage manager not set correctly");
    }

    function test_flash_RevertIfNotLeverageManager() public {
        vm.expectRevert(bytes("OLM")); // onlyLeverageManager modifier error
        flashMintSource.flash(address(0), 1e18, address(flashMintRecipient), "");
    }

    function test_flash_Success() public {
        uint256 flashAmount = 1000e18;
        uint256 expectedFee = flashAmount / 1000; // 0.1% fee

        vm.startPrank(leverageManager);
        IERC20(pod).transfer(address(flashMintRecipient), expectedFee);
        flashMintSource.flash(address(0), flashAmount, address(flashMintRecipient), bytes("called"));
        vm.stopPrank();

        // Verify flash mint recipient received the callback
        assertTrue(flashMintRecipient.lastCallbackData().length > 0, "Flash mint callback not called");
    }

    function test_flash_MinimumFee() public {
        uint256 flashAmount = 5; // Small amount where 0.1% would be 0
        uint256 expectedFee = 1; // Minimum fee is 1

        vm.startPrank(leverageManager);
        IERC20(pod).transfer(address(flashMintRecipient), expectedFee);
        flashMintSource.flash(address(0), flashAmount, address(flashMintRecipient), bytes("called"));
        vm.stopPrank();

        assertTrue(flashMintRecipient.lastCallbackData().length > 0, "Flash mint callback not called");
    }

    function test_callback_RevertIfNotSource() public {
        // First start a flash to initialize workflow
        uint256 flashAmount = 1000e18;
        uint256 expectedFee = flashAmount / 1000;

        vm.startPrank(leverageManager);
        IERC20(pod).transfer(address(flashMintRecipient), expectedFee);
        flashMintSource.flash(address(0), flashAmount, address(flashMintRecipient), "");
        vm.stopPrank();

        // Now try to call callback from non-source address
        vm.expectRevert(bytes("F1")); // Callback verification error
        vm.prank(address(0));
        flashMintSource.callback("");
    }

    function test_callback_RevertIfWorkflowIncorrect() public {
        vm.startPrank(pod);
        vm.expectRevert(bytes("F1")); // Workflow error - not initialized
        flashMintSource.callback("");
        vm.stopPrank();
    }

    function test_callback_Success() public {
        uint256 flashAmount = 1000e18;
        uint256 expectedFee = flashAmount / 1000;

        vm.startPrank(leverageManager);
        IERC20(pod).transfer(address(flashMintRecipient), expectedFee);
        flashMintSource.flash(address(0), flashAmount, address(flashMintRecipient), "test data");
        vm.stopPrank();

        // Verify the callback data was received
        assertEq(flashMintRecipient.lastCallbackData(), "test data", "Callback data not passed correctly");
    }

    function test_RevertIfReentrancy() public {
        // First start a flash to initialize workflow
        uint256 flashAmount = 1000e18;
        uint256 expectedFee = flashAmount / 1000;

        vm.startPrank(leverageManager);
        IERC20(pod).transfer(address(this), expectedFee);
        vm.expectRevert(bytes("L")); // pod locked
        flashMintSource.flash(address(0), flashAmount, address(this), "");
        vm.stopPrank();
    }

    function callback(bytes memory) external {
        uint256 flashAmount = 1000e18;
        uint256 expectedFee = flashAmount / 1000;

        vm.startPrank(leverageManager);
        IERC20(pod).transfer(address(flashMintRecipient), expectedFee);
        flashMintSource.flash(address(0), 1e3, address(flashMintRecipient), "");
        vm.stopPrank();
    }
}
