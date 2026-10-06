// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Slabs} from "../src/Slabs.sol";

/// @dev Test fixture only. The caller is distinct from the actual token deployer.
contract FactoryFixture {
    function deploy(bytes32 salt) external returns (Slabs) {
        return new Slabs{salt: salt}();
    }
}

contract SlabsTest is Test {
    uint256 private constant SUPPLY = 1e27;
    address private constant ALICE = address(0xA11CE);
    address private constant BOB = address(0xB0B);
    address private constant SPENDER = address(0x5EED);

    Slabs private token;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function setUp() public {
        token = new Slabs();
    }

    function testMetadataAndEntireInitialSupply() public view {
        assertEq(token.name(), "Slabs");
        assertEq(token.symbol(), "SLABS");
        assertEq(token.decimals(), 18);
        assertEq(token.INITIAL_SUPPLY(), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(address(0)), 0);
    }

    function testConstructorEmitsOneMintToImmediateDeployer() public {
        vm.recordLogs();
        vm.prank(ALICE);
        Slabs deployed = new Slabs();
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(logs.length, 1);
        assertEq(logs[0].emitter, address(deployed));
        assertEq(logs[0].topics.length, 3);
        assertEq(logs[0].topics[0], keccak256("Transfer(address,address,uint256)"));
        assertEq(logs[0].topics[1], bytes32(0));
        assertEq(logs[0].topics[2], bytes32(uint256(uint160(ALICE))));
        assertEq(abi.decode(logs[0].data, (uint256)), SUPPLY);
        assertEq(deployed.balanceOf(ALICE), SUPPLY);
        assertEq(deployed.balanceOf(address(this)), 0);
    }

    function testCreate2FactoryReceivesWholeSupply() public {
        FactoryFixture factory = new FactoryFixture();
        bytes32 salt = keccak256("Slabs test deployment");
        address predicted = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(bytes1(0xff), address(factory), salt, keccak256(type(Slabs).creationCode))
                    )
                )
            )
        );

        vm.prank(ALICE);
        Slabs deployed = factory.deploy(salt);
        assertEq(address(deployed), predicted);
        assertEq(deployed.balanceOf(address(factory)), SUPPLY);
        assertEq(deployed.totalSupply(), SUPPLY);
        assertEq(deployed.balanceOf(ALICE), 0);
    }

    function testLaunchStyleDistributionAndPoolTransfersArriveWhole() public {
        FactoryFixture factory = new FactoryFixture();
        Slabs deployed = factory.deploy(bytes32(uint256(1)));
        address distributor = address(0xD157);
        address poolManager = address(0x9001);
        uint256 swarm = SUPPLY / 10;
        uint256 pool = SUPPLY * 3 / 10;
        uint256 remainder = SUPPLY - swarm - pool;

        // Representative token movements only; pool allocation is not a launch parameter.
        vm.startPrank(address(factory));
        assertTrue(deployed.transfer(distributor, swarm));
        assertTrue(deployed.transfer(poolManager, pool));
        assertTrue(deployed.transfer(ALICE, remainder));
        vm.stopPrank();
        assertEq(deployed.balanceOf(address(factory)), 0);
        assertEq(deployed.balanceOf(distributor), swarm);
        assertEq(deployed.balanceOf(poolManager), pool);
        assertEq(deployed.balanceOf(ALICE), remainder);

        vm.prank(distributor);
        assertTrue(deployed.transfer(BOB, swarm));
        assertEq(deployed.balanceOf(distributor), 0);
        assertEq(deployed.balanceOf(BOB), swarm);

        vm.prank(poolManager);
        assertTrue(deployed.transfer(SPENDER, 7 ether));
        assertEq(deployed.balanceOf(SPENDER), 7 ether);
        assertEq(deployed.balanceOf(poolManager), pool - 7 ether);
        vm.prank(SPENDER);
        assertTrue(deployed.transfer(poolManager, 7 ether));
        assertEq(deployed.balanceOf(SPENDER), 0);
        assertEq(deployed.balanceOf(poolManager), pool);
        assertEq(deployed.totalSupply(), SUPPLY);
    }

    function testTransferEmitsEventAndMovesExactAmount() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), ALICE, 123 ether);
        assertTrue(token.transfer(ALICE, 123 ether));
        assertEq(token.balanceOf(address(this)), SUPPLY - 123 ether);
        assertEq(token.balanceOf(ALICE), 123 ether);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testWholeBalanceCanMoveAndReturnWithoutFee() public {
        assertTrue(token.transfer(ALICE, SUPPLY));
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(ALICE), SUPPLY);
        vm.prank(ALICE);
        assertTrue(token.transfer(address(this), SUPPLY));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testZeroTransferFromEmptyAccountEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(ALICE, BOB, 0);
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, 0));
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testSelfTransferDoesNotChangeBalanceOrSupply() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), address(this), SUPPLY);
        assertTrue(token.transfer(address(this), SUPPLY));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testTransferToZeroRevertsIncludingZeroAmount() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 1);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testInsufficientBalanceRevertsWithoutMovingTokens() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, 0, 1));
        vm.prank(ALICE);
        token.transfer(BOB, 1);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testApprovalEmitsEventCanBeReplacedAndRevoked() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(address(this), SPENDER, 20 ether);
        assertTrue(token.approve(SPENDER, 20 ether));
        assertEq(token.allowance(address(this), SPENDER), 20 ether);
        assertTrue(token.approve(SPENDER, 7 ether));
        assertEq(token.allowance(address(this), SPENDER), 7 ether);
        assertTrue(token.approve(SPENDER, 0));
        assertEq(token.allowance(address(this), SPENDER), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 0, 1));
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, 1);
    }

    function testApproveZeroSpenderReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 1);
        assertEq(token.allowance(address(this), address(0)), 0);
    }

    function testDelegatedTransferEmitsEventAndConsumesFiniteAllowance() public {
        assertTrue(token.approve(SPENDER, 10 ether));
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), ALICE, 4 ether);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, 4 ether));
        assertEq(token.allowance(address(this), SPENDER), 6 ether);
        assertEq(token.balanceOf(ALICE), 4 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY - 4 ether);

        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, 6 ether));
        assertEq(token.allowance(address(this), SPENDER), 0);
        assertEq(token.balanceOf(ALICE), 10 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY - 10 ether);
        assertEq(token.balanceOf(SPENDER), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testMaximumAllowanceIsNotDecreased() public {
        assertTrue(token.approve(SPENDER, type(uint256).max));
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, SUPPLY));
        assertEq(token.allowance(address(this), SPENDER), type(uint256).max);
        assertEq(token.balanceOf(ALICE), SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testZeroDelegatedTransferNeedsNoAllowance() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(ALICE, BOB, 0);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(ALICE, BOB, 0));
        assertEq(token.allowance(ALICE, SPENDER), 0);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), 0);
    }

    function testDelegatedSelfTransferConsumesAllowanceWithoutMovingBalance() public {
        assertTrue(token.approve(SPENDER, 10 ether));
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), address(this), 10 ether));
        assertEq(token.allowance(address(this), SPENDER), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testDeployerCannotSpendHolderTokensWithoutApproval() public {
        assertTrue(token.transfer(ALICE, 10 ether));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1));
        token.transferFrom(ALICE, BOB, 1);
        assertEq(token.balanceOf(ALICE), 10 ether);
        assertEq(token.balanceOf(BOB), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - 10 ether);
    }

    function testInsufficientAllowanceRevertsAndPreservesState() public {
        assertTrue(token.approve(SPENDER, 10 ether));
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 10 ether, 10 ether + 1)
        );
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, 10 ether + 1);
        assertEq(token.allowance(address(this), SPENDER), 10 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
    }

    function testDelegatedInsufficientBalanceRollsBackAllowance() public {
        vm.prank(ALICE);
        assertTrue(token.approve(SPENDER, 100 ether));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, 0, 100 ether));
        vm.prank(SPENDER);
        token.transferFrom(ALICE, BOB, 100 ether);
        assertEq(token.allowance(ALICE, SPENDER), 100 ether);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testDelegatedTransferToZeroRollsBackAllowance() public {
        assertTrue(token.approve(SPENDER, 100 ether));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(SPENDER);
        token.transferFrom(address(this), address(0), 100 ether);
        assertEq(token.allowance(address(this), SPENDER), 100 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testDelegatedTransferFromZeroRevertsEvenForZeroAmount() public {
        // OpenZeppelin validates the allowance owner before performing the transfer.
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidApprover.selector, address(0)));
        token.transferFrom(address(0), ALICE, 0);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testNoMintBurnOrAdministrativeEntryPoints() public {
        assertTrue(token.transfer(ALICE, 100 ether));
        bytes[] memory calls = new bytes[](17);
        calls[0] = abi.encodeWithSignature("mint(address,uint256)", BOB, 1 ether);
        calls[1] = abi.encodeWithSignature("mint(uint256)", 1 ether);
        calls[2] = abi.encodeWithSignature("mint()");
        calls[3] = abi.encodeWithSignature("issue(uint256)", 1 ether);
        calls[4] = abi.encodeWithSignature("burn(uint256)", 1 ether);
        calls[5] = abi.encodeWithSignature("burnFrom(address,uint256)", ALICE, 1 ether);
        calls[6] = abi.encodeWithSignature("pause()");
        calls[7] = abi.encodeWithSignature("unpause()");
        calls[8] = abi.encodeWithSignature("blacklist(address)", ALICE);
        calls[9] = abi.encodeWithSignature("freeze(address)", ALICE);
        calls[10] = abi.encodeWithSignature("seize(address)", ALICE);
        calls[11] = abi.encodeWithSignature("setOwner(address)", BOB);
        calls[12] = abi.encodeWithSignature("transferOwnership(address)", BOB);
        calls[13] = abi.encodeWithSignature("setMinter(address)", BOB);
        calls[14] = abi.encodeWithSignature("initialize(address)", BOB);
        calls[15] = abi.encodeWithSignature("upgradeTo(address)", BOB);
        calls[16] = abi.encodeWithSignature("setTransfersEnabled(bool)", false);

        for (uint256 i; i < calls.length; ++i) {
            (bool deployerSucceeded,) = address(token).call(calls[i]);
            assertFalse(deployerSucceeded);
            vm.prank(BOB);
            (bool strangerSucceeded,) = address(token).call(calls[i]);
            assertFalse(strangerSucceeded);
            assertEq(token.balanceOf(ALICE), 100 ether);
            assertEq(token.balanceOf(BOB), 0);
            assertEq(token.totalSupply(), SUPPLY);
        }

        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, 100 ether));
        assertEq(token.balanceOf(BOB), 100 ether);
    }

    function testRuntimeHasNoForbiddenOpcodes() public view {
        bytes memory runtime = address(token).code;
        assertGt(runtime.length, 0);
        assertLe(runtime.length, 24_576);
        for (uint256 i; i < runtime.length; ++i) {
            uint8 op = uint8(runtime[i]);
            if (op >= 0x60 && op <= 0x7f) {
                i += op - 0x5f;
                continue;
            }
            assertTrue(op != 0xf4 && op != 0xf2 && op != 0xff);
        }
    }

    function testFuzzTransferConservesSupplyAndChargesNoFee(uint256 amount) public {
        amount = bound(amount, 0, SUPPLY);
        assertTrue(token.transfer(ALICE, amount));
        assertEq(token.balanceOf(ALICE), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, amount));
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzzDelegatedTransferChargesNoFee(uint256 approved, uint256 amount) public {
        approved = bound(approved, 0, SUPPLY);
        amount = bound(amount, 0, approved);
        assertTrue(token.approve(SPENDER, approved));
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, amount));
        assertEq(token.allowance(address(this), SPENDER), approved - amount);
        assertEq(token.balanceOf(ALICE), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.balanceOf(SPENDER), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzzTransferAboveBalanceReverts(uint256 amount) public {
        amount = bound(amount, SUPPLY + 1, type(uint256).max);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, amount)
        );
        token.transfer(ALICE, amount);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }
}
