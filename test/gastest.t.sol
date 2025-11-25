// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import "../src/TicketMaster.sol";

contract TicketMasterGasTest is Test {
    TicketMaster public ticketMaster;
    address public organizer = address(0x1);
    address public buyer = address(0x2);
    address public feeRecipient = address(0x3);

    function setUp() public {
        ticketMaster = new TicketMaster(feeRecipient);
    }

    // FIXED: testGas_GetDynamicPriceWithDifferentDemand
    // The issue was trying to mint after reaching max supply
    function testGas_GetDynamicPriceWithDifferentDemand() public {
        vm.prank(organizer);
        uint256 eventId = ticketMaster.createEvent(
            "Concert",
            "metadata",
            100,
            1 ether,
            block.timestamp,
            block.timestamp + 1 days,
            true,
            true,  // dynamic pricing enabled
            500,
            address(0)
        );

        console.log("=== getDynamicPrice Gas at Different Demand Levels ===");

        // 0% sold - measure gas
        uint256 gasBefore = gasleft();
        uint256 price0 = ticketMaster.getDynamicPrice(eventId);
        uint256 gas0 = gasBefore - gasleft();
        console.log("0% sold:", gas0);

        // Mint 10 tickets (10% of 100)
        uint256 price = ticketMaster.getDynamicPrice(eventId);
        vm.prank(buyer);
        vm.deal(buyer, price * 10 + 1 ether);
        ticketMaster.mintTicket{value: price * 10}(eventId, 10);

        // 10% sold - measure gas
        uint256 gasBeforeTen = gasleft();
        uint256 price10 = ticketMaster.getDynamicPrice(eventId);
        uint256 gas10 = gasBeforeTen - gasleft();
        console.log("10% sold:", gas10);

        // Verify prices are reasonable
        assertGt(price10, price0, "Price should increase with demand");
        assertTrue(price10 <= 1.5 ether, "Price should not exceed 50% increase");
    }

    function testGas_CreateEvent() public {
        uint256 gasBefore = gasleft();
        
        vm.prank(organizer);
        ticketMaster.createEvent(
            "Concert",
            "metadata",
            1000,
            1 ether,
            block.timestamp,
            block.timestamp + 7 days,
            true,
            false,
            500,
            address(0)
        );
        
        uint256 gasUsed = gasBefore - gasleft();
        console.log("Gas used for createEvent:", gasUsed);
    }

    function testGas_GetDynamicPrice() public {
        vm.prank(organizer);
        uint256 eventId = ticketMaster.createEvent(
            "Concert",
            "metadata",
            100,
            1 ether,
            block.timestamp,
            block.timestamp + 1 days,
            true,
            true,
            500,
            address(0)
        );

        uint256 gasBefore = gasleft();
        ticketMaster.getDynamicPrice(eventId);
        uint256 gasUsed = gasBefore - gasleft();
        console.log("Gas used for getDynamicPrice:", gasUsed);
    }

    function testGas_MintSingleTicket() public {
        vm.prank(organizer);
        uint256 eventId = ticketMaster.createEvent(
            "Concert",
            "metadata",
            100,
            1 ether,
            block.timestamp,
            block.timestamp + 1 days,
            true,
            false,
            500,
            address(0)
        );

        uint256 price = ticketMaster.getDynamicPrice(eventId);
        uint256 gasBefore = gasleft();
        
        vm.prank(buyer);
        vm.deal(buyer, price);
        ticketMaster.mintTicket{value: price}(eventId, 1);
        
        uint256 gasUsed = gasBefore - gasleft();
        console.log("Gas used for minting 1 ticket:", gasUsed);
    }

    function testGas_MintMultipleTickets() public {
        vm.prank(organizer);
        uint256 eventId = ticketMaster.createEvent(
            "Concert",
            "metadata",
            100,
            1 ether,
            block.timestamp,
            block.timestamp + 1 days,
            true,
            false,
            500,
            address(0)
        );

        uint256 quantity = 10;
        uint256 price = ticketMaster.getDynamicPrice(eventId);
        uint256 totalPrice = price * quantity;

        uint256 gasBefore = gasleft();
        
        vm.prank(buyer);
        vm.deal(buyer, totalPrice);
        ticketMaster.mintTicket{value: totalPrice}(eventId, quantity);
        
        uint256 gasUsed = gasBefore - gasleft();
        console.log("Gas used for minting 10 tickets:", gasUsed);
    }

    function testGas_LargeBatchMint() public {
        vm.prank(organizer);
        uint256 eventId = ticketMaster.createEvent(
            "Concert",
            "metadata",
            100,
            1 ether,
            block.timestamp,
            block.timestamp + 1 days,
            true,
            false,
            500,
            address(0)
        );

        uint256 quantity = 10;  // Max batch
        uint256 price = ticketMaster.getDynamicPrice(eventId);
        uint256 totalPrice = price * quantity;

        uint256 gasBefore = gasleft();
        
        vm.prank(buyer);
        vm.deal(buyer, totalPrice);
        ticketMaster.mintTicket{value: totalPrice}(eventId, quantity);
        
        uint256 gasUsed = gasBefore - gasleft();
        uint256 gasPerTicket = gasUsed / quantity;
        console.log("Gas used for max batch (10 tickets):", gasUsed);
        console.log("Gas per ticket:", gasPerTicket);
    }

    function testGas_MintProgression() public {
        console.log("=== Mint Gas Progression ===");
        uint256[] memory quantities = new uint256[](5);
        quantities[0] = 1;
        quantities[1] = 2;
        quantities[2] = 5;
        quantities[3] = 8;
        quantities[4] = 10;

        for (uint256 i = 0; i < quantities.length; ++i) {
            vm.prank(organizer);
            uint256 eventId = ticketMaster.createEvent(
                string(abi.encodePacked("Event", vm.toString(i))),
                "metadata",
                100,
                1 ether,
                block.timestamp,
                block.timestamp + 1 days,
                true,
                false,
                500,
                address(0)
            );

            uint256 quantity = quantities[i];
            uint256 price = ticketMaster.getDynamicPrice(eventId);
            uint256 totalPrice = price * quantity;

            uint256 gasBefore = gasleft();
            
            vm.prank(buyer);
            vm.deal(buyer, totalPrice);
            ticketMaster.mintTicket{value: totalPrice}(eventId, quantity);
            
            uint256 gasUsed = gasBefore - gasleft();
            uint256 gasPerTicket = gasUsed / quantity;
            
            console.log("Quantity:", quantity);
            console.log("Gas used:", gasUsed);
            console.log("Gas per ticket:", gasPerTicket);
            console.log("---");
        }
    }

    function testGas_SequentialMintsVsBatch() public {
        console.log("=== Sequential vs Batch Minting ===");

        // Test 1: 10 sequential mints
        vm.prank(organizer);
        uint256 eventId1 = ticketMaster.createEvent(
            "Sequential",
            "metadata",
            100,
            1 ether,
            block.timestamp,
            block.timestamp + 1 days,
            true,
            false,
            500,
            address(0)
        );

        address sequential = address(0x10);
        uint256 price = ticketMaster.getDynamicPrice(eventId1);
        
        uint256 gasBefore = gasleft();
        for (uint256 i = 0; i < 10; ++i) {
            vm.prank(sequential);
            vm.deal(sequential, price);
            ticketMaster.mintTicket{value: price}(eventId1, 1);
        }
        uint256 gasSequential = gasBefore - gasleft();
        console.log("10 sequential mints (total gas):", gasSequential);

        // Test 2: 1 batch mint of 10
        vm.prank(organizer);
        uint256 eventId2 = ticketMaster.createEvent(
            "Batch",
            "metadata",
            100,
            1 ether,
            block.timestamp,
            block.timestamp + 1 days,
            true,
            false,
            500,
            address(0)
        );

        address batch = address(0x11);
        uint256 totalPrice = price * 10;
        
        uint256 gasBefore2 = gasleft();
        vm.prank(batch);
        vm.deal(batch, totalPrice);
        ticketMaster.mintTicket{value: totalPrice}(eventId2, 10);
        uint256 gasBatch = gasBefore2 - gasleft();
        console.log("1 batch mint of 10 (total gas):", gasBatch);

        uint256 savings = gasSequential - gasBatch;
        uint256 percentSavings = (savings * 100) / gasSequential;
        console.log("Gas saved by batching:", savings);
        console.log("Efficiency gain (%):", percentSavings);
    }

    function testGas_VerifyTicket() public {
        vm.prank(organizer);
        uint256 eventId = ticketMaster.createEvent(
            "Concert",
            "metadata",
            100,
            1 ether,
            block.timestamp,
            block.timestamp + 1 days,
            true,
            false,
            500,
            address(0)
        );

        uint256 price = ticketMaster.getDynamicPrice(eventId);
        vm.prank(buyer);
        vm.deal(buyer, price);
        ticketMaster.mintTicket{value: price}(eventId, 1);

        uint256[] memory tickets = ticketMaster.getUserTickets(eventId, buyer);
        uint256 ticketId = tickets[0];

        uint256 gasBefore = gasleft();
        ticketMaster.verifyTicket(ticketId, buyer);
        uint256 gasUsed = gasBefore - gasleft();
        console.log("Gas used for verifyTicket:", gasUsed);
    }

    function testGas_TransferSingleVsMultiple() public {
        console.log("=== Transfer Gas Comparison ===");

        // Create event
        vm.prank(organizer);
        uint256 eventId = ticketMaster.createEvent(
            "Concert",
            "metadata",
            100,
            1 ether,
            block.timestamp,
            block.timestamp + 1 days,
            true,
            false,
            500,
            address(0)
        );

        // Mint 6 tickets
        uint256 price = ticketMaster.getDynamicPrice(eventId);
        uint256 totalPrice = price * 6;
        vm.prank(buyer);
        vm.deal(buyer, totalPrice);
        ticketMaster.mintTicket{value: totalPrice}(eventId, 6);

        uint256[] memory allTickets = ticketMaster.getUserTickets(eventId, buyer);

        // Test 1: Single ticket transfer
        uint256[] memory singleTicket = new uint256[](1);
        singleTicket[0] = allTickets[0];

        uint256 gasBefore1 = gasleft();
        vm.prank(buyer);
        ticketMaster.safeTransferFromWithRoyalty(buyer, address(0x5), eventId, 1, singleTicket);
        uint256 gasSingle = gasBefore1 - gasleft();
        console.log("Single ticket transfer:", gasSingle);

        // Test 2: 5 tickets batch transfer
        uint256[] memory multipleTickets = new uint256[](5);
        for (uint256 i = 0; i < 5; ++i) {
            multipleTickets[i] = allTickets[i + 1];
        }

        uint256 gasBefore2 = gasleft();
        vm.prank(buyer);
        ticketMaster.safeTransferFromWithRoyalty(buyer, address(0x6), eventId, 5, multipleTickets);
        uint256 gasMultiple = gasBefore2 - gasleft();
        console.log("5 tickets batch transfer:", gasMultiple);

        uint256 gasPerTicketBatch = gasMultiple / 5;
        console.log("Gas per ticket (batch):", gasPerTicketBatch);

        if (gasSingle > 0) {
            uint256 efficiency = ((gasSingle - gasPerTicketBatch) * 100) / gasSingle;
            console.log("Efficiency gain: %d %%", efficiency);
        }
    }

    function testGas_TransferWithRoyalty() public {
        vm.prank(organizer);
        uint256 eventId = ticketMaster.createEvent(
            "Concert",
            "metadata",
            100,
            1 ether,
            block.timestamp,
            block.timestamp + 1 days,
            true,
            true,
            500,  // 5% royalty
            address(0)
        );

        // Mint 2 tickets
        uint256 price = ticketMaster.getDynamicPrice(eventId);
        uint256 totalPrice = price * 2;
        vm.prank(buyer);
        vm.deal(buyer, totalPrice + 1 ether);
        ticketMaster.mintTicket{value: totalPrice}(eventId, 2);

        uint256[] memory tickets = ticketMaster.getUserTickets(eventId, buyer);
        uint256[] memory ticketIds = new uint256[](2);
        ticketIds[0] = tickets[0];
        ticketIds[1] = tickets[1];

        uint256 gasBefore = gasleft();
        vm.prank(buyer);
        ticketMaster.safeTransferFromWithRoyalty{value: 0.5 ether}(
            buyer,
            address(0x7),
            eventId,
            2,
            ticketIds
        );
        uint256 gasUsed = gasBefore - gasleft();
        console.log("Gas used for transfer with royalty (2 tickets):", gasUsed);
    }

    function testGas_DynamicPricingImpact() public {
        console.log("=== Dynamic Pricing Gas Impact ===");

        // Event with dynamic pricing
        vm.prank(organizer);
        uint256 dynamicEventId = ticketMaster.createEvent(
            "Dynamic",
            "metadata",
            100,
            1 ether,
            block.timestamp,
            block.timestamp + 1 days,
            true,
            true,  // dynamic pricing enabled
            500,
            address(0)
        );

        // Event without dynamic pricing
        vm.prank(organizer);
        uint256 staticEventId = ticketMaster.createEvent(
            "Static",
            "metadata",
            100,
            1 ether,
            block.timestamp,
            block.timestamp + 1 days,
            true,
            false,  // dynamic pricing disabled
            500,
            address(0)
        );

        uint256 quantity = 5;
        uint256 staticPrice = ticketMaster.getDynamicPrice(staticEventId);
        uint256 totalPrice = staticPrice * quantity;

        // Measure static pricing
        address buyer1 = address(0x20);
        uint256 gasBefore1 = gasleft();
        vm.prank(buyer1);
        vm.deal(buyer1, totalPrice);
        ticketMaster.mintTicket{value: totalPrice}(staticEventId, quantity);
        uint256 gasStatic = gasBefore1 - gasleft();
        console.log("Static pricing - 5 tickets:", gasStatic);

        // Measure dynamic pricing
        address buyer2 = address(0x21);
        uint256 dynamicPrice = ticketMaster.getDynamicPrice(dynamicEventId);
        uint256 totalDynamic = dynamicPrice * quantity;
        
        uint256 gasBefore2 = gasleft();
        vm.prank(buyer2);
        vm.deal(buyer2, totalDynamic);
        ticketMaster.mintTicket{value: totalDynamic}(dynamicEventId, quantity);
        uint256 gasDynamic = gasBefore2 - gasleft();
        console.log("Dynamic pricing - 5 tickets:", gasDynamic);

        uint256 diff = gasDynamic > gasStatic ? gasDynamic - gasStatic : gasStatic - gasDynamic;
        console.log("Gas difference:", diff);
    }
}