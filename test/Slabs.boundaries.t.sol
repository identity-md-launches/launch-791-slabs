// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Slabs} from "../src/Slabs.sol";

/// forge-config: default.fuzz.runs = 1000
contract SlabsBoundaryTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 1e18;
    address private constant ALICE = address(0xA11CE);
    address private constant BOB = address(0xB0B);
    address private constant SPENDER = address(0x5EED);
    address private constant OTHER_SPENDER = address(0x5EEE);

    Slabs private token;

    function setUp() public {
        token = new Slabs();
    }

    function testOneWeiDirectAndDelegatedRoundTripHasNoFee() public {
        assertTrue(token.transfer(ALICE, 1));
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
        assertEq(token.balanceOf(ALICE), 1);
        vm.prank(ALICE);
        assertTrue(token.approve(SPENDER, 1));
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(ALICE, address(this), 1));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(SPENDER), 0);
        assertEq(token.allowance(ALICE, SPENDER), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testMaximumTransferAndDelegatedTransferRevertWithoutOverflow() public {
        uint256 maximum = type(uint256).max;
        assertTrue(token.approve(SPENDER, maximum));
        bytes memory expected =
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, maximum);
        vm.expectRevert(expected);
        token.transfer(ALICE, maximum);
        vm.expectRevert(expected);
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, maximum);
        assertEq(token.allowance(address(this), SPENDER), maximum);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testLargestFiniteAllowanceIsDecreased() public {
        uint256 approved = type(uint256).max - 1;
        assertTrue(token.approve(SPENDER, approved));
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, SUPPLY));
        assertEq(token.allowance(address(this), SPENDER), approved - SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(ALICE), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testExhaustedAllowanceCannotBeUsedTwice() public {
        assertTrue(token.approve(SPENDER, 1));
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, 1));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 0, 1));
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, 1);
        assertEq(token.allowance(address(this), SPENDER), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
        assertEq(token.balanceOf(ALICE), 1);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testInfiniteAllowanceCanBeReplacedThenRevoked() public {
        assertTrue(token.approve(SPENDER, type(uint256).max));
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, 1));
        assertEq(token.allowance(address(this), SPENDER), type(uint256).max);

        assertTrue(token.approve(SPENDER, 2));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 2, 3));
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, 3);
        assertEq(token.allowance(address(this), SPENDER), 2);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, 1));
        assertEq(token.allowance(address(this), SPENDER), 1);

        assertTrue(token.approve(SPENDER, 0));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 0, 1));
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, 1);
        assertEq(token.balanceOf(address(this)), SUPPLY - 2);
        assertEq(token.balanceOf(ALICE), 2);
        assertEq(token.allowance(address(this), SPENDER), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testSelfTransferAboveBalanceStillReverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, SUPPLY + 1)
        );
        token.transfer(address(this), SUPPLY + 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testOwnerUsingTransferFromMustApproveItself() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1));
        token.transferFrom(address(this), ALICE, 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);

        assertTrue(token.approve(address(this), 1));
        assertTrue(token.transferFrom(address(this), ALICE, 1));
        assertEq(token.allowance(address(this), address(this)), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
        assertEq(token.balanceOf(ALICE), 1);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzzAllowancesAreIsolatedByOwnerAndSpender(uint256 approved) public {
        approved = bound(approved, 1, SUPPLY / 2);
        assertTrue(token.transfer(ALICE, SUPPLY / 2));
        assertTrue(token.approve(SPENDER, approved));
        vm.prank(ALICE);
        assertTrue(token.approve(OTHER_SPENDER, approved));

        // Same spender, different owner: authorization on the deployer cannot debit Alice.
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 0, 1));
        vm.prank(SPENDER);
        token.transferFrom(ALICE, BOB, 1);
        // Same owner, different spender: Alice's approval cannot authorize the deployer's funds.
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, OTHER_SPENDER, 0, 1));
        vm.prank(OTHER_SPENDER);
        token.transferFrom(address(this), BOB, 1);
        assertEq(token.allowance(address(this), SPENDER), approved);
        assertEq(token.allowance(ALICE, OTHER_SPENDER), approved);
        assertEq(token.allowance(ALICE, SPENDER), 0);
        assertEq(token.allowance(address(this), OTHER_SPENDER), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY / 2);
        assertEq(token.balanceOf(ALICE), SUPPLY / 2);
        assertEq(token.balanceOf(BOB), 0);

        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), BOB, approved));
        assertEq(token.allowance(address(this), SPENDER), 0);
        assertEq(token.allowance(ALICE, OTHER_SPENDER), approved);
        vm.prank(OTHER_SPENDER);
        assertTrue(token.transferFrom(ALICE, BOB, approved));
        assertEq(token.allowance(ALICE, OTHER_SPENDER), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY / 2 - approved);
        assertEq(token.balanceOf(ALICE), SUPPLY / 2 - approved);
        assertEq(token.balanceOf(BOB), approved * 2);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzzFundedOwnerRejectsSpendingAboveAllowance(uint256 approved, uint256 amount) public {
        amount = bound(amount, 1, SUPPLY);
        approved = bound(approved, 0, amount - 1);
        assertTrue(token.approve(SPENDER, approved));
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, approved, amount)
        );
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, amount);
        assertEq(token.allowance(address(this), SPENDER), approved);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzzFailedDelegatedOverdraftPreservesAllowanceAndCanRecover(
        uint256 balance,
        uint256 amount,
        bool infinite
    ) public {
        balance = bound(balance, 1, SUPPLY);
        amount = bound(amount, balance + 1, type(uint256).max - 1);
        uint256 approved = infinite ? type(uint256).max : amount;
        assertTrue(token.transfer(ALICE, balance));
        vm.prank(ALICE);
        assertTrue(token.approve(SPENDER, approved));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, balance, amount));
        vm.prank(SPENDER);
        token.transferFrom(ALICE, BOB, amount);
        assertEq(token.allowance(ALICE, SPENDER), approved);
        assertEq(token.balanceOf(ALICE), balance);
        assertEq(token.balanceOf(BOB), 0);

        // A rejected spend must neither consume authorization nor lock subsequent valid transfers.
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(ALICE, BOB, balance));
        assertEq(token.allowance(ALICE, SPENDER), infinite ? approved : approved - balance);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), balance);
        assertEq(token.balanceOf(address(this)), SUPPLY - balance);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzzRepeatedApprovalOverwritesWithoutMovingTokens(uint256 initial, uint256 replacement) public {
        assertTrue(token.approve(SPENDER, initial));
        assertEq(token.allowance(address(this), SPENDER), initial);
        assertTrue(token.approve(SPENDER, replacement));
        assertEq(token.allowance(address(this), SPENDER), replacement);
        assertTrue(token.approve(SPENDER, replacement));
        assertEq(token.allowance(address(this), SPENDER), replacement);
        assertEq(token.allowance(address(this), OTHER_SPENDER), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(SPENDER), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }
}
