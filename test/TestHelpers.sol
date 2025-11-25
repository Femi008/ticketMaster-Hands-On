// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import "../src/TicketMaster.sol";

contract TestHelpers is Test {
    TicketMaster public ticketMaster;
    uint256 public eventId;
    address feeRecipient = address(0x1111111111111111111111111111111111111111);
    address organizer = address(0x2222222222222222222222222222222222222222);

    function setUp() public {
        // Create TicketMaster with proper fee recipient
        ticketMaster = new TicketMaster(feeRecipient);

        // Fund organizer
        vm.deal(organizer, 100 ether);

        // Create event as organizer
        vm.prank(organizer);
        eventId = ticketMaster.createEvent(
            "Concert",
            "metadata",
            100,
            0.1 ether,
            block.timestamp,
            block.timestamp + 1 days,
            true,
            false,
            500,
            address(0)
        );
    }

    function testMintTickets() public {
        // Get the price for this event
        uint256 price = ticketMaster.getDynamicPrice(eventId);
        require(price > 0, "Price should be greater than 0");
        
        // Create a buyer and fund them
        address buyer = address(0x9999);
        vm.deal(buyer, 10 ether);
        
        // Mint 1 ticket as the buyer
        vm.prank(buyer);
        ticketMaster.mintTicket{value: price}(eventId, 1);
        
        // Verify the ticket was minted
        uint256[] memory userTickets = ticketMaster.getUserTickets(eventId, buyer);
        require(userTickets.length == 1, "Should have 1 ticket");
    }

    function testMintMultipleTickets() public {
        uint256 quantity = 5;
        uint256 price = ticketMaster.getDynamicPrice(eventId);
        require(price > 0, "Price should be greater than 0");
        
        uint256 totalPrice = price * quantity;
        
        // Create a buyer and fund them
        address buyer = address(0x8888);
        vm.deal(buyer, totalPrice + 1 ether);
        
        // Mint tickets as the buyer
        vm.prank(buyer);
        ticketMaster.mintTicket{value: totalPrice}(eventId, quantity);
        
        // Verify using getAvailableTickets
        uint256 available = ticketMaster.getAvailableTickets(eventId);
        uint256 expected = 100 - quantity;
        require(available == expected, "Available tickets should decrease");
    }

    function testGetEventDetails() public {
        ITicketMaster.Event memory evt = ticketMaster.getEvent(eventId);
        require(keccak256(abi.encodePacked(evt.name)) == keccak256(abi.encodePacked("Concert")), "Event name should match");
        require(evt.maxSupply == 100, "Max supply should be 100");
        require(evt.price == 0.1 ether, "Price should be 0.1 ether");
        require(evt.transferable == true, "Event should be transferable");
    }

    function testGetUserTickets() public {
        uint256 quantity = 3;
        uint256 price = ticketMaster.getDynamicPrice(eventId);
        require(price > 0, "Price should be greater than 0");
        
        uint256 totalPrice = price * quantity;
        
        // Create a buyer and fund them
        address buyer = address(0x7777);
        vm.deal(buyer, totalPrice + 1 ether);
        
        // Mint tickets as the buyer
        vm.prank(buyer);
        ticketMaster.mintTicket{value: totalPrice}(eventId, quantity);
        
        uint256[] memory tickets = ticketMaster.getUserTickets(eventId, buyer);
        require(tickets.length == 3, "Should have 3 tickets");
    }
}