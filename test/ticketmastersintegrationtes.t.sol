// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import "../src/TicketMaster.sol";


/**
 * @title TicketMasterIntegrationTest
 * @dev Advanced integration and scenario tests for TicketMaster
 */
contract TicketMasterIntegrationTest is Test {
    TicketMaster public ticketMaster;
    
    address public platformFeeRecipient = makeAddr("platform");
    address public organizer1 = makeAddr("organizer1");
    address public organizer2 = makeAddr("organizer2");
    address public buyer1 = makeAddr("buyer1");
    address public buyer2 = makeAddr("buyer2");
    address public buyer3 = makeAddr("buyer3");
    address public scalper = makeAddr("scalper");
    
    uint256 constant TICKET_PRICE = 0.1 ether;
    uint256 constant MAX_SUPPLY = 100;
    
    function setUp() public {
        ticketMaster = new TicketMaster(platformFeeRecipient);
        
        // Fund accounts
        vm.deal(organizer1, 100 ether);
        vm.deal(organizer2, 100 ether);
        vm.deal(buyer1, 100 ether);
        vm.deal(buyer2, 100 ether);
        vm.deal(buyer3, 100 ether);
        vm.deal(scalper, 100 ether);
    }

    // ============================================
    // COMPLETE LIFECYCLE TESTS
    // ============================================

    function testCompleteEventLifecycle() public {
        // 1. Organizer creates event
        vm.startPrank(organizer1);
        uint256 startTime = block.timestamp + 7 days;
        uint256 endTime = startTime + 3 hours;
        
        uint256 eventId = ticketMaster.createEvent(
            "Rock Concert",
            "ipfs://QmConcert",
            MAX_SUPPLY,
            TICKET_PRICE,
            startTime,
            endTime,
            true,
            1000 // 10% royalty
        );
        vm.stopPrank();
        
        // 2. Multiple buyers purchase tickets
        vm.prank(buyer1);
        ticketMaster.mintTicket{value: TICKET_PRICE * 5}(eventId, 5);
        
        vm.prank(buyer2);
        ticketMaster.mintTicket{value: TICKET_PRICE * 3}(eventId, 3);
        
        vm.prank(buyer3);
        ticketMaster.mintTicket{value: TICKET_PRICE * 2}(eventId, 2);
        
        // Verify sales
        assertEq(ticketMaster.balanceOf(buyer1, eventId), 5);
        assertEq(ticketMaster.balanceOf(buyer2, eventId), 3);
        assertEq(ticketMaster.balanceOf(buyer3, eventId), 2);
        assertEq(ticketMaster.getAvailableTickets(eventId), MAX_SUPPLY - 10);
        
        // 3. Secondary market transfer
        vm.prank(buyer1);
        ticketMaster.safeTransferFromWithRoyalty{value: 0.15 ether}(
            buyer1,
            scalper,
            eventId,
            2
        );
        
        assertEq(ticketMaster.balanceOf(buyer1, eventId), 3);
        assertEq(ticketMaster.balanceOf(scalper, eventId), 2);
        
        // 4. Event day - tickets used
        vm.warp(startTime);
        
        vm.prank(buyer1);
        ticketMaster.burnTicket(eventId, 3);
        
        vm.prank(scalper);
        ticketMaster.burnTicket(eventId, 2);
        
        assertEq(ticketMaster.balanceOf(buyer1, eventId), 0);
        assertEq(ticketMaster.balanceOf(scalper, eventId), 0);
    }

    function testMultipleEventsScenario() public {
        // Create multiple events from different organizers
        vm.prank(organizer1);
        uint256 event1 = ticketMaster.createEvent(
            "Music Festival",
            "ipfs://Qm1",
            1000,
            0.2 ether,
            block.timestamp + 30 days,
            block.timestamp + 31 days,
            true,
            500
        );
        
        vm.prank(organizer2);
        uint256 event2 = ticketMaster.createEvent(
            "Tech Conference",
            "ipfs://Qm2",
            500,
            0.5 ether,
            block.timestamp + 60 days,
            block.timestamp + 63 days,
            false, // Non-transferable
            250
        );
        
        // Same user buys tickets to both events
        vm.startPrank(buyer1);
        ticketMaster.mintTicket{value: 0.2 ether * 5}(event1, 5);
        ticketMaster.mintTicket{value: 0.5 ether * 2}(event2, 2);
        vm.stopPrank();
        
        assertEq(ticketMaster.balanceOf(buyer1, event1), 5);
        assertEq(ticketMaster.balanceOf(buyer1, event2), 2);
        
        // Can transfer music festival tickets
        vm.prank(buyer1);
        ticketMaster.safeTransferFromWithRoyalty{value: 0.3 ether}(
            buyer1,
            buyer2,
            event1,
            2
        );
        
        // Cannot transfer conference tickets
        vm.prank(buyer1);
        vm.expectRevert("Tickets are non-transferable");
        ticketMaster.safeTransferFromWithRoyalty{value: 0.6 ether}(
            buyer1,
            buyer2,
            event2,
            1
        );
    }

    // ============================================
    // STRESS TESTS
    // ============================================

    function testSellOutScenario() public {
        uint256 smallSupply = 20;
        
        vm.prank(organizer1);
        uint256 eventId = ticketMaster.createEvent(
            "Exclusive Show",
            "ipfs://QmExclusive",
            smallSupply,
            TICKET_PRICE,
            block.timestamp + 1 days,
            block.timestamp + 2 days,
            true,
            500
        );
        
        // Multiple buyers compete for tickets
        vm.prank(buyer1);
        ticketMaster.mintTicket{value: TICKET_PRICE * 8}(eventId, 8);
        
        vm.prank(buyer2);
        ticketMaster.mintTicket{value: TICKET_PRICE * 7}(eventId, 7);
        
        vm.prank(buyer3);
        ticketMaster.mintTicket{value: TICKET_PRICE * 5}(eventId, 5);
        
        // Event is sold out
        assertEq(ticketMaster.getAvailableTickets(eventId), 0);
        
        // Additional purchase fails
        vm.prank(scalper);
        vm.expectRevert("Exceeds max supply");
        ticketMaster.mintTicket{value: TICKET_PRICE}(eventId, 1);
    }

    function testMassiveBatchMint() public {
        vm.prank(organizer1);
        uint256 eventId = ticketMaster.createEvent(
            "Conference",
            "ipfs://QmConf",
            1000,
            TICKET_PRICE,
            block.timestamp + 1 days,
            block.timestamp + 4 days,
            true,
            250
        );
        
        // Create 50 VIP recipients
        address[] memory vips = new address[](50);
        uint256[] memory quantities = new uint256[](50);
        
        for (uint256 i = 0; i < 50; i++) {
            vips[i] = address(uint160(i + 1000));
            quantities[i] = 2;
        }
        
        vm.prank(organizer1);
        ticketMaster.batchMintTickets(eventId, vips, quantities);
        
        // Verify all received tickets
        for (uint256 i = 0; i < 50; i++) {
            assertEq(ticketMaster.balanceOf(vips[i], eventId), 2);
        }
        
        ITicketMaster.Event memory evt = ticketMaster.getEvent(eventId);
        assertEq(evt.totalMinted, 100);
    }

    // ============================================
    // ECONOMIC TESTS
    // ============================================

    function testRoyaltyDistribution() public {
        vm.prank(organizer1);
        uint256 eventId = ticketMaster.createEvent(
            "Art Exhibition",
            "ipfs://QmArt",
            100,
            1 ether,
            block.timestamp + 1 days,
            block.timestamp + 30 days,
            true,
            1500 // 15% royalty
        );
        
        // Primary sale
        vm.prank(buyer1);
        ticketMaster.mintTicket{value: 1 ether}(eventId, 1);
        
        uint256 organizerBalanceBefore = organizer1.balance;
        
        // Secondary sale at 2x price
        uint256 resalePrice = 2 ether;
        uint256 expectedRoyalty = (resalePrice * 1500) / 10000; // 0.3 ether
        
        vm.prank(buyer1);
        ticketMaster.safeTransferFromWithRoyalty{value: resalePrice}(
            buyer1,
            buyer2,
            eventId,
            1
        );
        
        assertEq(organizer1.balance, organizerBalanceBefore + expectedRoyalty);
    }

    function testPlatformFeeAccumulation() public {
        uint256 platformBalanceBefore = platformFeeRecipient.balance;
        
        vm.prank(organizer1);
        uint256 eventId = ticketMaster.createEvent(
            "Sports Game",
            "ipfs://QmSports",
            1000,
            TICKET_PRICE,
            block.timestamp + 1 days,
            block.timestamp + 2 days,
            true,
            500
        );
        
        // Multiple sales
        uint256 totalSales = 0;
        
        vm.prank(buyer1);
        ticketMaster.mintTicket{value: TICKET_PRICE * 10}(eventId, 10);
        totalSales += TICKET_PRICE * 10;
        
        vm.prank(buyer2);
        ticketMaster.mintTicket{value: TICKET_PRICE * 15}(eventId, 15);
        totalSales += TICKET_PRICE * 15;
        
        vm.prank(buyer3);
        ticketMaster.mintTicket{value: TICKET_PRICE * 20}(eventId, 20);
        totalSales += TICKET_PRICE * 20;
        
        uint256 expectedFees = (totalSales * 250) / 10000; // 2.5%
        assertEq(
            platformFeeRecipient.balance,
            platformBalanceBefore + expectedFees
        );
    }

    // ============================================
    // EDGE CASES & SECURITY
    // ============================================

    function testCannotBuyFromInactiveEvent() public {
        vm.prank(organizer1);
        uint256 eventId = ticketMaster.createEvent(
            "Cancelled Show",
            "ipfs://QmCancel",
            100,
            TICKET_PRICE,
            block.timestamp + 1 days,
            block.timestamp + 2 days,
            true,
            500
        );
        
        // Organizer deactivates
        vm.prank(organizer1);
        ticketMaster.setEventStatus(eventId, false);
        
        // Purchase attempt fails
        vm.prank(buyer1);
        vm.expectRevert("Event is not active");
        ticketMaster.mintTicket{value: TICKET_PRICE}(eventId, 1);
    }

    function testReentrancyProtection() public {
        // This test ensures the nonReentrant modifier works
        // In a real attack scenario, the attacker would try to re-enter
        // during the payment callback
        
        MaliciousReceiver attacker = new MaliciousReceiver(ticketMaster);
        vm.deal(address(attacker), 10 ether);
        
        vm.prank(organizer1);
        uint256 eventId = ticketMaster.createEvent(
            "Target Event",
            "ipfs://QmTarget",
            100,
            TICKET_PRICE,
            block.timestamp + 1 days,
            block.timestamp + 2 days,
            true,
            500
        );
        
        // Attacker tries to exploit reentrancy
        vm.prank(address(attacker));
        vm.expectRevert();
        attacker.attack{value: TICKET_PRICE}(eventId);
    }

    function testApprovalAndTransfer() public {
        vm.prank(organizer1);
        uint256 eventId = ticketMaster.createEvent(
            "Concert",
            "ipfs://QmConcert",
            100,
            TICKET_PRICE,
            block.timestamp + 1 days,
            block.timestamp + 2 days,
            true,
            500
        );
        
        vm.prank(buyer1);
        ticketMaster.mintTicket{value: TICKET_PRICE * 5}(eventId, 5);
        
        // Approve buyer2 to transfer
        vm.prank(buyer1);
        ticketMaster.setApprovalForAll(buyer2, true);
        
        // Buyer2 transfers on behalf of buyer1
        vm.prank(buyer2);
        ticketMaster.safeTransferFrom(
            buyer1,
            buyer3,
            eventId,
            2,
            ""
        );
        
        assertEq(ticketMaster.balanceOf(buyer1, eventId), 3);
        assertEq(ticketMaster.balanceOf(buyer3, eventId), 2);
    }

    // ============================================
    // TIME-BASED TESTS
    // ============================================

    function testEmergencyWithdrawTiming() public {
        vm.prank(organizer1);
        uint256 eventId = ticketMaster.createEvent(
            "Future Event",
            "ipfs://QmFuture",
            100,
            TICKET_PRICE,
            block.timestamp + 30 days,
            block.timestamp + 31 days,
            true,
            500
        );
        
        // Can withdraw before event starts (no sales)
        vm.prank(organizer1);
        ticketMaster.emergencyWithdraw(eventId);
        
        ITicketMaster.Event memory evt = ticketMaster.getEvent(eventId);
        assertFalse(evt.active);
    }

    function testCannotWithdrawAfterEventStarts() public {
        vm.prank(organizer1);
        uint256 eventId = ticketMaster.createEvent(
            "Current Event",
            "ipfs://QmCurrent",
            100,
            TICKET_PRICE,
            block.timestamp + 1 hours,
            block.timestamp + 2 hours,
            true,
            500
        );
        
        // Warp to event time
        vm.warp(block.timestamp + 1 hours + 1);
        
        vm.prank(organizer1);
        vm.expectRevert("Event already started");
        ticketMaster.emergencyWithdraw(eventId);
    }

    // ============================================
    // BATCH OPERATIONS
    // ============================================

    function testBatchTransfer() public {
        vm.prank(organizer1);
        uint256 event1 = ticketMaster.createEvent(
            "Event 1",
            "ipfs://Qm1",
            100,
            TICKET_PRICE,
            block.timestamp + 1 days,
            block.timestamp + 2 days,
            true,
            500
        );
        
        vm.prank(organizer1);
        uint256 event2 = ticketMaster.createEvent(
            "Event 2",
            "ipfs://Qm2",
            100,
            TICKET_PRICE,
            block.timestamp + 3 days,
            block.timestamp + 4 days,
            true,
            500
        );
        
        // Buy tickets for both events
        vm.startPrank(buyer1);
        ticketMaster.mintTicket{value: TICKET_PRICE * 5}(event1, 5);
        ticketMaster.mintTicket{value: TICKET_PRICE * 3}(event2, 3);
        vm.stopPrank();
        
        // Batch transfer
        uint256[] memory ids = new uint256[](2);
        ids[0] = event1;
        ids[1] = event2;
        
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 2;
        amounts[1] = 1;
        
        vm.prank(buyer1);
        ticketMaster.safeBatchTransferFrom(
            buyer1,
            buyer2,
            ids,
            amounts,
            ""
        );
        
        assertEq(ticketMaster.balanceOf(buyer1, event1), 3);
        assertEq(ticketMaster.balanceOf(buyer1, event2), 2);
        assertEq(ticketMaster.balanceOf(buyer2, event1), 2);
        assertEq(ticketMaster.balanceOf(buyer2, event2), 1);
    }

    function testBatchBurn() public {
        vm.prank(organizer1);
        uint256 event1 = ticketMaster.createEvent(
            "Event 1",
            "ipfs://Qm1",
            100,
            TICKET_PRICE,
            block.timestamp + 1 days,
            block.timestamp + 2 days,
            true,
            500
        );
        
        vm.prank(organizer1);
        uint256 event2 = ticketMaster.createEvent(
            "Event 2",
            "ipfs://Qm2",
            100,
            TICKET_PRICE,
            block.timestamp + 3 days,
            block.timestamp + 4 days,
            true,
            500
        );
        
        vm.startPrank(buyer1);
        ticketMaster.mintTicket{value: TICKET_PRICE * 5}(event1, 5);
        ticketMaster.mintTicket{value: TICKET_PRICE * 3}(event2, 3);
        
        // Burn multiple tickets at once
        ticketMaster.burnTicket(event1, 2);
        ticketMaster.burnTicket(event2, 1);
        
        assertEq(ticketMaster.balanceOf(buyer1, event1), 3);
        assertEq(ticketMaster.balanceOf(buyer1, event2), 2);
        vm.stopPrank();
    }
}

// ============================================
// MOCK CONTRACTS FOR TESTING
// ============================================

contract MaliciousReceiver {
    TicketMaster public ticketMaster;
    bool public attacking;
    
    constructor(TicketMaster _ticketMaster) {
        ticketMaster = _ticketMaster;
    }
    
    function attack(uint256 eventId) external payable {
        attacking = true;
        ticketMaster.mintTicket{value: msg.value}(eventId, 1);
    }
    
    receive() external payable {
        if (attacking) {
            // Try to re-enter
            attacking = false;
            // This should fail due to reentrancy guard
            ticketMaster.mintTicket{value: 0.1 ether}(0, 1);
        }
    }
}