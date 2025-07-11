// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

contract EventContract {
  // Mapping from event id to event
  mapping(bytes32 => Event) public events;
  bytes32[] public event_id_list;
  uint8 constant public max_ticket_types = 100;
  mapping(address => bytes32[]) public participation;

  struct Event { // attempt strict packaging
    address payable owner;
    bytes32 event_id; //unique
    bytes32 title;
    uint index;
    uint256 max_per_customer;
    uint256 funds;
    bool exists;
    bool sale_active;
    bool buyback_active;
    bool per_customer_limit;
    uint256 deadline;
    uint256[] available_tickets;
    uint256[] ticket_prices;
    address[] customers;
    mapping(address => Customer) tickets;
  }

  struct Customer {
    uint index;
    address addr;
    bool exists;
    uint256 total_num_tickets;
    uint256 total_paid;
    uint256[] num_tickets;
  }

  event EventCreated(bytes32 event_id);

  modifier eventExists(bytes32 event_id){
    require(events[event_id].exists, "Event with given ID not found.");
    _;
  }

  modifier onlyHost(bytes32 event_id){
    require(events[event_id].owner == msg.sender, "Sender is not the owner of this event");
    _;
  }

  modifier beforeDeadline(bytes32 event_id){
      require(events[event_id].deadline > block.timestamp, "Event deadline has passed");
      _;
  }

  modifier afterDeadline(bytes32 event_id){
      require(events[event_id].deadline < block.timestamp, "Event deadline has not yet passed");
      _;
  }

function getVersion() public pure returns (string memory) {
        return "Version 1.0"; // Hardcode or use the `version` variable
    }

// ----- Event host functions -----

  function create_event(bytes32 _event_id,
    bytes32 _title,
    uint256[] calldata num_tickets,
    uint256[] calldata _ticket_prices,
    bool _per_customer_limit,
    uint256 _max_per_customer,
    bool _sale_active,
    bool _buyback_active,
    uint256 _deadline) external {
      require(!events[_event_id].exists, "Given event ID is already in use.");
      require(num_tickets.length == _ticket_prices.length,
        "Different number of ticket types given by price and number available arrays.");
      require(num_tickets.length > 0, "Cannot create event with zero ticket types.");
      require(num_tickets.length <= max_ticket_types, "Maximum number of ticket types exceeded.");
      require(_deadline > block.timestamp, "Deadline cannot be in the past");
      events[_event_id].exists = true;
      events[_event_id].event_id = _event_id;
      events[_event_id].title = _title;
      events[_event_id].available_tickets = num_tickets;
      events[_event_id].ticket_prices = _ticket_prices;
      events[_event_id].max_per_customer = _max_per_customer;
      events[_event_id].per_customer_limit = _per_customer_limit;
      events[_event_id].owner = payable(msg.sender);
      events[_event_id].sale_active = _sale_active;
      events[_event_id].buyback_active = _buyback_active;
      events[_event_id].deadline = _deadline;
      events[_event_id].index = event_id_list.length;
      event_id_list.push(_event_id);
      emit EventCreated(_event_id);
  }

  // Add these events for better tracking:  
  event TicketPurchased(bytes32 indexed event_id, address indexed customer, uint256 ticket_type, uint256 quantity, uint256 amount);
  event TicketReturned(bytes32 indexed event_id, address indexed customer, uint256 refund_amount);
  event FundsWithdrawn(bytes32 indexed event_id, address indexed owner, uint256 amount);
  event EventDeleted(bytes32 indexed event_id);

  function withdraw_funds(bytes32 event_id) external eventExists(event_id) onlyHost(event_id) afterDeadline(event_id) {
    events[event_id].buyback_active = false;
    uint256 withdraw_amount = events[event_id].funds;
    events[event_id].funds = 0;

    emit FundsWithdrawn(event_id, msg.sender, withdraw_amount);


    (bool success, ) = events[event_id].owner.call{value: withdraw_amount}("");
    require(success, "Withdrawal transfer failed.");
  }

  function view_funds(bytes32 event_id) external view eventExists(event_id) onlyHost(event_id) returns (uint256 current_funds){
    return events[event_id].funds;
  }

  function get_tickets(bytes32 event_id, address customer) external view eventExists(event_id)
        returns (uint256[] memory) {
    return events[event_id].tickets[customer].num_tickets;
  }

  function get_customers(bytes32 event_id) external view eventExists(event_id)
        returns (address[] memory) {
    return (events[event_id].customers);
  }

  function stop_sale(bytes32 event_id) external eventExists(event_id) onlyHost(event_id) {
    events[event_id].sale_active = false;
  }

  function continue_sale(bytes32 event_id) external eventExists(event_id) onlyHost(event_id) {
    events[event_id].sale_active = true;
  }

  function add_tickets(bytes32 event_id, uint256[] calldata additional_tickets) external eventExists(event_id) onlyHost(event_id) {
    require(additional_tickets.length == events[event_id].available_tickets.length,
      "List of number of tickets to add must be of same length as existing list of tickets.");

    for(uint256 i = 0; i < events[event_id].available_tickets.length ; i++) {
      // Check for overflow (even though Solidity 0.8+ has built-in protection)
      require(events[event_id].available_tickets[i] + additional_tickets[i] >= events[event_id].available_tickets[i],
              "Cannot exceed maximum tickets");
      events[event_id].available_tickets[i] += additional_tickets[i];
    }
}

  function change_ticket_price(bytes32 event_id, uint256 ticket_type, uint256 new_price) external eventExists(event_id) onlyHost(event_id) {
    require(ticket_type < events[event_id].ticket_prices.length, "Ticket type does not exist.");
    events[event_id].ticket_prices[ticket_type] = new_price;
  }

  function delete_event(bytes32 event_id) external eventExists(event_id) onlyHost(event_id) {
    require(events[event_id].funds == 0, "Cannot delete event with positive funds.");
    require(events[event_id].deadline + 604800 < block.timestamp,
      "Cannot delete event before a week has passed since deadline");

    uint old_index = events[event_id].index;
        emit EventDeleted(event_id);

    delete events[event_id];
    
    // Handle array element removal correctly
    if (old_index != event_id_list.length - 1) {
        bytes32 last_event_id = event_id_list[event_id_list.length - 1];
        event_id_list[old_index] = last_event_id;
        events[last_event_id].index = old_index;
    }
    event_id_list.pop();
}

// ----- Customer functions -----

  function buy_tickets(bytes32 event_id, uint256 ticket_type, uint256 requested_num_tickets) external payable eventExists(event_id) beforeDeadline(event_id) {
    require(requested_num_tickets > 0);
    require(ticket_type < events[event_id].available_tickets.length, "Ticket type does not exist.");
    require(events[event_id].sale_active, "Ticket sale is closed by seller.");
    require(requested_num_tickets <= events[event_id].available_tickets[ticket_type],
      "Not enough tickets available.");
    require(!events[event_id].per_customer_limit ||
      (events[event_id].tickets[msg.sender].total_num_tickets + requested_num_tickets <= events[event_id].max_per_customer),
      "Purchase surpasses max per customer.");
    uint256 sum_price = uint256(requested_num_tickets)*uint256(events[event_id].ticket_prices[ticket_type]);
    require(msg.value >= sum_price, "Not enough ether was sent.");

    if(!events[event_id].tickets[msg.sender].exists) {
      events[event_id].tickets[msg.sender].exists = true;
      events[event_id].tickets[msg.sender].addr = msg.sender;
      events[event_id].tickets[msg.sender].index = events[event_id].customers.length;
      events[event_id].customers.push(msg.sender);
      events[event_id].tickets[msg.sender].num_tickets = new uint256[](events[event_id].available_tickets.length);
    }

    events[event_id].tickets[msg.sender].total_num_tickets += requested_num_tickets;
    events[event_id].tickets[msg.sender].num_tickets[ticket_type] += requested_num_tickets;
    events[event_id].tickets[msg.sender].total_paid += sum_price;
    events[event_id].available_tickets[ticket_type] -= requested_num_tickets;
    events[event_id].funds += sum_price;

    add_participation(event_id, msg.sender);

    emit TicketPurchased(event_id, msg.sender, ticket_type, requested_num_tickets, sum_price);

    // Return excessive funds
    if(msg.value > sum_price) {
      (bool success, ) = msg.sender.call{value : msg.value - sum_price}("");
      require(success, "Return of excess funds to sender failed.");
    }
  }

  function return_tickets(bytes32 event_id) external eventExists(event_id) beforeDeadline(event_id) {
    require(events[event_id].tickets[msg.sender].total_num_tickets > 0,
      "User does not own any tickets to this event.");
    require(events[event_id].buyback_active, "Ticket buyback has been deactivated by owner.");
    require(events[event_id].sale_active, "Ticket sale is locked, which disables buyback.");

    uint256 return_amount = events[event_id].tickets[msg.sender].total_paid;

    for(uint256 i = 0; i < events[event_id].available_tickets.length ; i++) {
      // Check for overflow when returning tickets
      require(events[event_id].available_tickets[i] + events[event_id].tickets[msg.sender].num_tickets[i] >= events[event_id].available_tickets[i],
              "Failed because returned tickets would increase ticket pool past storage limit.");
      events[event_id].available_tickets[i] += events[event_id].tickets[msg.sender].num_tickets[i];
    }

    delete_customer(event_id, msg.sender);
    delete_participation(event_id, msg.sender);

    events[event_id].funds -= return_amount;
    emit TicketReturned(event_id, msg.sender, return_amount);


    (bool success, ) = msg.sender.call{value: return_amount}("");
    require(success, "Return transfer to customer failed.");
}

// ----- View functions -----

  function get_event_info(bytes32 event_id) 
    external 
    view 
    eventExists(event_id) 
    returns (
        bytes32 id,
        bytes32 title,
        address owner,
        uint256 deadline,
        uint256[] memory available_tickets,
        uint256 max_per_customer,
        uint256[] memory ticket_price,
        bool sale_active,
        bool buyback_active,
        bool per_customer_limit
    ) {
    return (
        events[event_id].event_id,
        events[event_id].title,
        events[event_id].owner,
        events[event_id].deadline,
        events[event_id].available_tickets,
        events[event_id].max_per_customer,
        events[event_id].ticket_prices,
        events[event_id].sale_active,
        events[event_id].buyback_active,
        events[event_id].per_customer_limit
    );
}

  function get_events() external view returns (bytes32[] memory event_list) {
    return event_id_list;
  }

  function get_participation() external view returns (bytes32[] memory event_participation) {
    require(participation[msg.sender].length > 0, "Sender does not own any tickets.");
    return participation[msg.sender];
  }

// ----- Internal functions -----

  function delete_customer(bytes32 event_id, address customer_addr) internal {
    uint old_index = events[event_id].tickets[customer_addr].index;
    delete events[event_id].tickets[customer_addr];
    
    // Handle array element removal correctly
    if (old_index != events[event_id].customers.length - 1) {
      events[event_id].customers[old_index] = events[event_id].customers[events[event_id].customers.length - 1];
      events[event_id].tickets[events[event_id].customers[old_index]].index = old_index;
    }
    events[event_id].customers.pop();
  }

  function add_participation(bytes32 event_id, address customer_addr) internal {
    for(uint256 i = 0; i < participation[customer_addr].length ; i++) {
      if (participation[customer_addr][i] == event_id) {
        return;
      }
    }
    participation[customer_addr].push(event_id);
  }

  function delete_participation(bytes32 event_id, address customer_addr) internal {
    uint len = participation[customer_addr].length;
    for(uint256 i = 0; i < len ; i++) {
      if (participation[customer_addr][i] == event_id) {
        if (i != len - 1) {
          participation[customer_addr][i] = participation[customer_addr][len-1];
        }
        participation[customer_addr].pop();
        break;
      }
    }
  }
}