// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Slabs} from "../src/Slabs.sol";

/// @dev Restricts movement to four actors so their balances account for every token.
/// Each action checks exact deltas as well as the global conservation invariant.
contract SlabsHandler is Test {
    Slabs public immutable token;
    address[4] public actors = [address(0x1001), address(0x1002), address(0x1003), address(0x1004)];

    constructor(Slabs token_) {
        token = token_;
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 fromBefore = token.balanceOf(from);
        uint256 toBefore = token.balanceOf(to);
        amount = bound(amount, 0, fromBefore);
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        _assertMovement(from, to, fromBefore, toBefore, amount);
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        assertEq(token.allowance(owner, spender), amount);
    }

    function transferFrom(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 allowanceBefore = token.allowance(owner, spender);
        uint256 fromBefore = token.balanceOf(owner);
        uint256 toBefore = token.balanceOf(to);
        uint256 available = allowanceBefore < fromBefore ? allowanceBefore : fromBefore;
        amount = bound(amount, 0, available);
        vm.prank(spender);
        assertTrue(token.transferFrom(owner, to, amount));
        _assertMovement(owner, to, fromBefore, toBefore, amount);
        assertEq(
            token.allowance(owner, spender),
            allowanceBefore == type(uint256).max ? allowanceBefore : allowanceBefore - amount
        );
    }

    function _assertMovement(address from, address to, uint256 fromBefore, uint256 toBefore, uint256 amount)
        private
        view
    {
        assertEq(token.balanceOf(from), from == to ? fromBefore : fromBefore - amount);
        assertEq(token.balanceOf(to), from == to ? toBefore : toBefore + amount);
    }
}

contract SlabsInvariantTest is Test {
    Slabs private token;
    SlabsHandler private handler;

    function setUp() public {
        token = new Slabs();
        handler = new SlabsHandler(token);
        assertTrue(token.transfer(handler.actors(0), 1e27));

        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = SlabsHandler.transfer.selector;
        selectors[1] = SlabsHandler.approve.selector;
        selectors[2] = SlabsHandler.transferFrom.selector;
        targetContract(address(handler));
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function invariantSupplyIsFixedAndAllBalancesAreConserved() public view {
        uint256 sum;
        for (uint256 i; i < 4; ++i) {
            sum += token.balanceOf(handler.actors(i));
        }
        assertEq(sum, 1e27);
        assertEq(token.totalSupply(), 1e27);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(0)), 0);
    }
}
