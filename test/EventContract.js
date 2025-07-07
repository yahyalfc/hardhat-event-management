const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("EventContract - Interaction Tests", function () {
  let contract;
  let owner, buyer, other;
  let eventId, title, deadline;
  const TICKETS = [1000];
  const TICKET_PRICE = ethers.parseEther("0.01"); // 0.01 ETH
  const ONE_DAY = 24 * 60 * 60;
  let events = [];

  beforeEach(async function () {
    [owner, buyer, other] = await ethers.getSigners();
    const EventContract = await ethers.getContractFactory("EventContract");
    contract = await EventContract.deploy();
    await contract.waitForDeployment();

    // Setup event parameters
    eventId = ethers.encodeBytes32String("TestEvent2");
    title = ethers.encodeBytes32String("This is the event title");
    deadline = Math.floor(Date.now() / 1000) + ONE_DAY; // 1 day from now

    // Create event for most tests
    await contract
      .connect(owner)
      .create_event(
        eventId,
        title,
        TICKETS,
        [TICKET_PRICE],
        false,
        0,
        true,
        true,
        deadline
      );

    events.push({
      id: eventId,
      num_tickets: 1000,
      ticket_price: TICKET_PRICE,
      per_customer_limit: false,
      max_per_customer: 0,
      owner: owner.address,
    });
  });

  it("should create an event", async function () {
    const newEventId = ethers.encodeBytes32String("TestEvent3");
    const newTitle = ethers.encodeBytes32String("Another event");

    await expect(
      contract
        .connect(owner)
        .create_event(
          newEventId,
          newTitle,
          TICKETS,
          [TICKET_PRICE],
          false,
          0,
          true,
          true,
          deadline
        )
    )
      .to.emit(contract, "EventCreated")
      .withArgs(newEventId);

    const event = await contract.get_event_info(newEventId);
    expect(event.id).to.equal(newEventId);
    expect(event.title).to.equal(newTitle);
    expect(event.owner).to.equal(owner.address);
    expect(event.available_tickets[0]).to.equal(TICKETS[0]);
    expect(event.ticket_price[0]).to.equal(TICKET_PRICE);
  });

  it("should revert get_participation for non-ticket holder", async function () {
    await expect(
      contract.connect(other).get_participation()
    ).to.be.revertedWith("Sender does not own any tickets.");
  });

  it("should buy tickets", async function () {
    let ticketsToBuy = 1;
    const purchase = await contract
      .connect(buyer)
      .buy_tickets(eventId, 0, ticketsToBuy, { value: TICKET_PRICE });
    const receipt = await purchase.wait();
    console.log(
      `     Gas used to buy ${ticketsToBuy} ticket(s): ${receipt.gasUsed}`
    );

    let buyerTickets = await contract.get_tickets(eventId, buyer.address);
    expect(buyerTickets[0]).to.equal(ticketsToBuy);

    const participation = await contract.connect(buyer).get_participation();
    expect(participation[0]).to.equal(eventId);

    ticketsToBuy = 5;
    const totalPrice = TICKET_PRICE * BigInt(ticketsToBuy);
    const purchase2 = await contract
      .connect(buyer)
      .buy_tickets(eventId, 0, ticketsToBuy, { value: totalPrice });
    const receipt2 = await purchase2.wait();
    console.log(
      `     Gas used to buy ${ticketsToBuy} ticket(s): ${receipt2.gasUsed}`
    );

    buyerTickets = await contract.get_tickets(eventId, buyer.address);
    expect(buyerTickets[0]).to.equal(6); // 1 + 5
  });

  it("should return tickets", async function () {
    const buyer2 = (await ethers.getSigners())[5];
    const ticketsToBuy = 5;
    const totalPrice = TICKET_PRICE * BigInt(ticketsToBuy);
    const balanceBefore = await ethers.provider.getBalance(buyer2.address);

    const purchase = await contract
      .connect(buyer2)
      .buy_tickets(eventId, 0, ticketsToBuy, { value: totalPrice });
    const purchaseReceipt = await purchase.wait();
    const purchaseGas = purchaseReceipt.gasUsed * purchaseReceipt.gasPrice;

    let buyerTickets = await contract.get_tickets(eventId, buyer2.address);
    expect(buyerTickets[0]).to.equal(ticketsToBuy);

    const returnTx = await contract.connect(buyer2).return_tickets(eventId);
    const returnReceipt = await returnTx.wait();
    const returnGas = returnReceipt.gasUsed * returnReceipt.gasPrice;

    // After returning tickets, the customer is deleted, so we expect an empty array
    buyerTickets = await contract.get_tickets(eventId, buyer2.address);
    expect(buyerTickets.length).to.equal(0);

    const balanceAfter = await ethers.provider.getBalance(buyer2.address);
    expect(balanceBefore - purchaseGas - returnGas).to.equal(balanceAfter);
  });

  it("should revert buying with insufficient amount", async function () {
    const ticketsToBuy = 1;
    const insufficientAmount = TICKET_PRICE / 2n;
    await expect(
      contract
        .connect(buyer)
        .buy_tickets(eventId, 0, ticketsToBuy, { value: insufficientAmount })
    ).to.be.revertedWith("Not enough ether was sent.");
  });

  it("should handle buying with excessive amount", async function () {
    const ticketsToBuy = 1;
    const excessiveAmount = TICKET_PRICE * 2n;
    const balanceBefore = await ethers.provider.getBalance(buyer.address);

    const purchase = await contract
      .connect(buyer)
      .buy_tickets(eventId, 0, ticketsToBuy, { value: excessiveAmount });
    const receipt = await purchase.wait();
    const gasCost = receipt.gasUsed * receipt.gasPrice;

    const balanceAfter = await ethers.provider.getBalance(buyer.address);
    expect(balanceBefore - TICKET_PRICE - gasCost).to.equal(balanceAfter);
  });

  it("should revert withdraw_funds from unauthorized address", async function () {
    await expect(
      contract.connect(other).withdraw_funds(eventId)
    ).to.be.revertedWith("Sender is not the owner of this event");
  });

  it("should stop and continue sale", async function () {
    await contract.connect(owner).stop_sale(eventId);
    let eventInfo = await contract.get_event_info(eventId);
    expect(eventInfo.sale_active).to.equal(false);

    await expect(
      contract
        .connect(buyer)
        .buy_tickets(eventId, 0, 1, { value: TICKET_PRICE })
    ).to.be.revertedWith("Ticket sale is closed by seller.");

    await contract.connect(owner).continue_sale(eventId);
    eventInfo = await contract.get_event_info(eventId);
    expect(eventInfo.sale_active).to.equal(true);
  });

  it("should add tickets", async function () {
    const initialTickets = (await contract.get_event_info(eventId))
      .available_tickets[0];
    await contract.connect(owner).add_tickets(eventId, [10]);
    const newTickets = (await contract.get_event_info(eventId))
      .available_tickets[0];
    expect(newTickets).to.equal(initialTickets + 10n);
  });

  it("should change ticket price", async function () {
    const oldPrice = (await contract.get_event_info(eventId)).ticket_price[0];
    const newPrice = oldPrice + ethers.parseEther("0.01");
    await contract.connect(owner).change_ticket_price(eventId, 0, newPrice);
    const updatedPrice = (await contract.get_event_info(eventId))
      .ticket_price[0];
    expect(updatedPrice).to.equal(newPrice);
  });

  it("should revert creating event with past deadline", async function () {
    const pastDeadline = Math.floor(Date.now() / 1000) - ONE_DAY;
    const pastEventId = ethers.encodeBytes32String("PastEvent");
    await expect(
      contract
        .connect(owner)
        .create_event(
          pastEventId,
          title,
          TICKETS,
          [TICKET_PRICE],
          false,
          0,
          true,
          true,
          pastDeadline
        )
    ).to.be.revertedWith("Deadline cannot be in the past");
  });

  it("should delete event after deadline", async function () {
    // Create a snapshot to revert state changes
    const snapshot = await ethers.provider.send("evm_snapshot", []);

    try {
      const deleteEventId = ethers.encodeBytes32String("TestEvent3");
      const deleteTitle = ethers.encodeBytes32String(
        "This event will be deleted soon"
      );
      const deleteDeadline = Math.floor(Date.now() / 1000) + ONE_DAY; // One day in the future

      await contract
        .connect(owner)
        .create_event(
          deleteEventId,
          deleteTitle,
          [10000],
          [ethers.parseEther("0.1")],
          false,
          0,
          true,
          true,
          deleteDeadline
        );

      // Advance time past deadline (1 day + 7 days = 8 days)
      await ethers.provider.send("evm_increaseTime", [8 * ONE_DAY]);
      await ethers.provider.send("evm_mine", []);

      await contract.connect(owner).delete_event(deleteEventId);
      await expect(contract.get_event_info(deleteEventId)).to.be.revertedWith(
        "Event with given ID not found."
      );
    } finally {
      // Revert the snapshot
      await ethers.provider.send("evm_revert", [snapshot]);
    }
  });

  // Additional test to ensure array manipulation works correctly
  it("should handle customer deletion correctly", async function () {
    const buyer2 = (await ethers.getSigners())[4];
    const buyer3 = (await ethers.getSigners())[5];

    // Buy tickets with multiple customers
    await contract
      .connect(buyer)
      .buy_tickets(eventId, 0, 1, { value: TICKET_PRICE });
    await contract
      .connect(buyer2)
      .buy_tickets(eventId, 0, 1, { value: TICKET_PRICE });
    await contract
      .connect(buyer3)
      .buy_tickets(eventId, 0, 1, { value: TICKET_PRICE });

    let customers = await contract.get_customers(eventId);
    expect(customers.length).to.equal(3);

    // Return tickets from middle customer
    await contract.connect(buyer2).return_tickets(eventId);

    customers = await contract.get_customers(eventId);
    expect(customers.length).to.equal(2);

    // Verify remaining customers are still valid
    const tickets1 = await contract.get_tickets(eventId, buyer.address);
    const tickets3 = await contract.get_tickets(eventId, buyer3.address);
    expect(tickets1[0]).to.equal(1);
    expect(tickets3[0]).to.equal(1);
  });
});
