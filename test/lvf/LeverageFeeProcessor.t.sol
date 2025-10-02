// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {LeverageFeeProcessor} from "../../contracts/lvf/LeverageFeeProcessor.sol";

contract MockERC20 {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }
}

contract LeverageFeeProcessorTest is Test {
    LeverageFeeProcessor public feeProcessor;
    MockERC20 public token;

    address public constant MAIN_FEE_RECEIVER = address(0x1);
    address public constant PARTNER = address(0x2);
    address public constant INSURANCE = address(0x3);
    address public constant POD = address(0x4);

    function setUp() public {
        feeProcessor = new LeverageFeeProcessor();
        token = new MockERC20();
    }

    function test_processFees_NoPartnerNoInsurance() public {
        uint256 totalFees = 1000e18;

        // Mint tokens to fee processor
        token.mint(address(feeProcessor), totalFees);

        uint256 mainReceiverBalBefore = token.balanceOf(MAIN_FEE_RECEIVER);

        // Process fees with no partner or insurance configured
        feeProcessor.processFees(POD, address(token), totalFees, MAIN_FEE_RECEIVER, true);

        // All fees should go to main receiver
        assertEq(token.balanceOf(MAIN_FEE_RECEIVER), mainReceiverBalBefore + totalFees);
        assertEq(token.balanceOf(PARTNER), 0);
        assertEq(token.balanceOf(INSURANCE), 0);
    }

    function test_processFees_WithPartner() public {
        uint256 totalFees = 1000e18;
        uint16 partnerFeePerc = 2000; // 20%

        // Set partner configuration
        feeProcessor.setPartnerConfig(POD, PARTNER, partnerFeePerc, partnerFeePerc, 0);

        // Mint tokens to fee processor
        token.mint(address(feeProcessor), totalFees);

        uint256 mainReceiverBalBefore = token.balanceOf(MAIN_FEE_RECEIVER);
        uint256 partnerBalBefore = token.balanceOf(PARTNER);

        // Process fees
        feeProcessor.processFees(POD, address(token), totalFees, MAIN_FEE_RECEIVER, true);

        uint256 expectedPartnerFee = (totalFees * partnerFeePerc) / 10000;
        uint256 expectedMainFee = totalFees - expectedPartnerFee;

        assertEq(token.balanceOf(PARTNER), partnerBalBefore + expectedPartnerFee);
        assertEq(token.balanceOf(MAIN_FEE_RECEIVER), mainReceiverBalBefore + expectedMainFee);
    }

    function test_processFees_WithInsurance() public {
        uint256 totalFees = 1000e18;
        uint16 insuranceFeePerc = 1000; // 10%

        // Set insurance configuration
        feeProcessor.setInsuranceConfig(INSURANCE, insuranceFeePerc);

        // Mint tokens to fee processor
        token.mint(address(feeProcessor), totalFees);

        uint256 mainReceiverBalBefore = token.balanceOf(MAIN_FEE_RECEIVER);
        uint256 insuranceBalBefore = token.balanceOf(INSURANCE);

        // Process fees
        feeProcessor.processFees(POD, address(token), totalFees, MAIN_FEE_RECEIVER, true);

        uint256 expectedInsuranceFee = (totalFees * insuranceFeePerc) / 10000;
        uint256 expectedMainFee = totalFees - expectedInsuranceFee;

        assertEq(token.balanceOf(INSURANCE), insuranceBalBefore + expectedInsuranceFee);
        assertEq(token.balanceOf(MAIN_FEE_RECEIVER), mainReceiverBalBefore + expectedMainFee);
    }

    function test_processFees_WithPartnerAndInsurance() public {
        uint256 totalFees = 1000e18;
        uint16 partnerFeePerc = 2000; // 20%
        uint16 insuranceFeePerc = 1000; // 10%

        // Set configurations
        feeProcessor.setPartnerConfig(POD, PARTNER, partnerFeePerc, partnerFeePerc, 0);
        feeProcessor.setInsuranceConfig(INSURANCE, insuranceFeePerc);

        // Mint tokens to fee processor
        token.mint(address(feeProcessor), totalFees);

        uint256 mainReceiverBalBefore = token.balanceOf(MAIN_FEE_RECEIVER);
        uint256 partnerBalBefore = token.balanceOf(PARTNER);
        uint256 insuranceBalBefore = token.balanceOf(INSURANCE);

        // Process fees
        feeProcessor.processFees(POD, address(token), totalFees, MAIN_FEE_RECEIVER, true);

        uint256 expectedPartnerFee = (totalFees * partnerFeePerc) / 10000;
        uint256 expectedInsuranceFee = (totalFees * insuranceFeePerc) / 10000;
        uint256 expectedMainFee = totalFees - expectedPartnerFee - expectedInsuranceFee;

        assertEq(token.balanceOf(PARTNER), partnerBalBefore + expectedPartnerFee);
        assertEq(token.balanceOf(INSURANCE), insuranceBalBefore + expectedInsuranceFee);
        assertEq(token.balanceOf(MAIN_FEE_RECEIVER), mainReceiverBalBefore + expectedMainFee);
    }

    function test_processFees_ExpiredPartner() public {
        uint256 totalFees = 1000e18;
        uint16 partnerFeePerc = 2000; // 20%

        // First set partner config with future expiration to verify it works
        uint256 futureExpiration = block.timestamp + 1000;
        feeProcessor.setPartnerConfig(POD, PARTNER, partnerFeePerc, partnerFeePerc, futureExpiration);

        // Mint tokens to fee processor
        token.mint(address(feeProcessor), totalFees);

        // Process fees - partner should get fees since not expired
        feeProcessor.processFees(POD, address(token), totalFees, MAIN_FEE_RECEIVER, true);

        uint256 expectedPartnerFee = (totalFees * partnerFeePerc) / 10000;
        assertEq(token.balanceOf(PARTNER), expectedPartnerFee);

        // Now test with expired partner
        uint256 totalFees2 = 500e18;

        // Move forward in time to make the partner expire
        vm.warp(block.timestamp + 2000); // Move past the expiration

        // Mint more tokens to fee processor
        token.mint(address(feeProcessor), totalFees2);

        uint256 mainReceiverBalBefore = token.balanceOf(MAIN_FEE_RECEIVER);
        uint256 partnerBalBefore = token.balanceOf(PARTNER);

        // Process fees
        feeProcessor.processFees(POD, address(token), totalFees2, MAIN_FEE_RECEIVER, true);

        // Partner should get nothing due to expiration, all fees go to main receiver
        assertEq(token.balanceOf(PARTNER), partnerBalBefore); // No change
        assertEq(token.balanceOf(MAIN_FEE_RECEIVER), mainReceiverBalBefore + totalFees2);
    }
}
