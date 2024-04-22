pragma solidity ^0.8.13;

// Import necessary contracts from OpenZeppelin library
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

// Contract definition for a Ticketing System, inheriting ERC721URIStorage
contract TicketingSystem is ERC721URIStorage {

    // define the modifier such that only the deployer can call specific functions
    address private deployer;
    modifier onlyEventDeployer() {
        require(msg.sender == deployer, "Only the event deployer can call this function");
        _;
    }

    // define the counter to store the NFT count
    using Counters for Counters.Counter;
    Counters.Counter private _ticketIds;
    
    // define the ticket structure
    struct Ticket {
        string eventName;
        string eventDetails;
        string seat;
        uint256 ticketId;
        uint256 price;
        uint8 transferCount;
        uint8 maxTransferCount;
    }

    // Global variables to store ticket and event details
    string public eventName;
    string public eventDetails;
    bool eventDetailsSet = false;
    uint8 public seatRows;
    uint8 public seatCols;
    bool seatingPlanSet = false;
    uint256 ticketTransferBaseCost;
    uint8 maxTransferCount;
    bool ticketPriceDetailsSet = false;

    // global state variables, keep track of ticket addresses, seats availability and seat prices
    mapping(address => Ticket) public tickets;
    mapping(address => bool) public ownsTicket;
    mapping(string => address) public seats;
    mapping(string => bool) public seatAvailability;
    mapping(string => uint256) public seatPrices;

    // define events for logging and emit them later
    event EventDetailsSet(address indexed deployer, string eventDetails);
    event SeatingPlanSet(address indexed deployer, uint8 seatRows, uint8 seatCols);
    event TicketPriceDetailsSet(address indexed deployer, uint8 maxTransferCount, uint256 ticketTransferBaseCost);
    event TicketCreated(uint256 ticketId, address indexed seatOwner, string seat, uint256 price);
    event TicketTransferred(uint256 ticketId, address indexed originalOwner, address indexed newOwner, string seat, uint256 transferCost);

    // Constructor to initialize the contract with the event name
    constructor(string memory _eventName) ERC721("Ticket", "TICKET") {
        eventName = _eventName;
        deployer = msg.sender;
    }

    // method to set the event details, can only be called by the event deployer
    function setEventDetails(string memory _eventDetails) 
        public onlyEventDeployer 
        returns (bool) {
        eventDetails = _eventDetails;
        eventDetailsSet = true;
        emit EventDetailsSet(msg.sender, _eventDetails);
        return true;
    }

    // method to set the seat details, can only be called by the event deployer
    // @return boolean true if thes seating plan is successfully emitted
    function setSeatingPlanDetails(
        uint8 _seatRows,
        uint8 _seatCols
    ) public onlyEventDeployer
    returns (bool) {
        // initialize the seat rows and seat columns
        require(seatRows <= 26, "Maximum row number can only be Z!");
        seatRows = _seatRows;
        seatCols = _seatCols;
        // set the seating plan, initialize all seats in the availability mapping as true
        // also set the prices
        string memory seat;
        string memory seatRow;
        string memory seatCol;
        uint256 seatPrice;
        // ensures that each seat has a price associated with it
        for (uint8 i = 1; i <= seatRows; i++) {
            seatRow = convertIntToStr(i);
            for (uint8 j = 1; j <= seatCols; j++) {
                seatCol = Strings.toString(j);
                seat = string.concat(seatRow, seatCol);
                seatAvailability[seat] = true;
                // set two different prices depending on the seat
                if (i <= seatRows / 2) {
                    seatPrice = 0.01 ether;
                }
                else {
                    seatPrice = 0.005 ether;
                }
                seatPrices[seat] = seatPrice;
            }
        }
        // emits seating plan
        seatingPlanSet = true;
        emit SeatingPlanSet(msg.sender, seatRows, seatCols);
        return true;
    }
    
    // method to set the ticket price details, can only be called by the event deployer
    // @return boolean true if the setting was successful
    function setTicketPriceDetails(
        uint8 _maxTransferCount)
        public onlyEventDeployer
        returns (bool) {
            maxTransferCount = _maxTransferCount;
            ticketTransferBaseCost = 0.0001 ether;
            ticketPriceDetailsSet = true;
            // emit TicketPriceDetails to the messagge sender
            emit TicketPriceDetailsSet(msg.sender,  maxTransferCount, ticketTransferBaseCost);
            return true;
        }
    
    //method to retrieve the ticket details owned by the caller
    //@return Ticket memory which is the details of the ticket 
    function getTicketDetails() public view returns (Ticket memory) {   
        Ticket memory ticket = tickets[msg.sender];
        uint256 _ticketId = ticket.ticketId;
        // require ticketID to be valid else return invalid ticket ID
        require(_ticketId > 0 && _ticketId <= _ticketIds.current(), 
                "Invalid ticket ID");
        return ticket;
    }

    // method to check if seat is taken
    // @param _seat the seat identifier
    // @return boolean true if seat is taken false otherwise
    function isSeatTaken(string memory _seat) public view returns (bool) {
        return !seatAvailability[_seat];
    }
    
    // method to get total number of tickets
    // @return number of total tickets
    function getTotalTickets() public view returns (uint256) {
        return seatRows * seatCols;
    }
    
    // method to get total number of sold tickets
    // @return number of total tickets sold
    function getTotalSoldTickets() public view returns (uint256) {
        return _ticketIds.current();
    }

    // method to get total number of availble tickets for sake
    // @return total number of tickets still available
    function getTotalAvailableTickets() public view returns (uint256) {
        return this.getTotalTickets() - this.getTotalSoldTickets();
    }

    // method to get the price of a ticket for a specific seat
    // @param _seat the seat identifier
    // @return the price of a ticket for a specific seat
    function getTicketPrice(string memory _seat) public view returns (uint256) {
        return seatPrices[_seat];
    }

    // function to create a new ticket, and mint a new NFT
    // @return the ticketID of the created ticket
    function createTicket(
        string memory _seat,
        string memory _tokenURI
    ) public payable returns (uint256) {
        // initialize a variable to count gas fees
        uint256 startGas = gasleft();

        // require event Details to have been properly set
        require(eventDetailsSet, "event details not yet properly set");
        // require seating plan to have been properly set
        require(seatingPlanSet, "seating plan not yet properly set");
        // require ticket price details to have been properly set
        require(ticketPriceDetailsSet, "ticket details not yet properly set");
        // require seat have not been taken
        require(!isSeatTaken(_seat), "Seat is already taken");
        // require message sender have not owned a ticket
        require(!ownsTicket[msg.sender], "You already owned a ticket!");
        
        // initialize price as the ticket price for the specific seat
        uint256 price = getTicketPrice(_seat);
        require(msg.value >= price, "Insufficient funds");

        _ticketIds.increment();
        uint256 ticketId = _ticketIds.current();

        // initialize a ticket object and its details
        Ticket memory newTicket = Ticket({
            eventName: eventName,
            eventDetails: eventDetails,
            seat: _seat,
            ticketId: ticketId,
            price: price,
            transferCount: 0,
            maxTransferCount: maxTransferCount
        });

        // Assign the newly created ticket to the sender's address in the tickets mapping.
        tickets[msg.sender] = newTicket;
        // Mint a new ERC721 token (NFT) and assign it to the sender's address.
        _mint(msg.sender, ticketId);
        // Set the metadata URI for the newly minted token.
        _setTokenURI(ticketId, _tokenURI);
        // Associate the seat identifier with the sender's address in the seats mapping, indicating ownership.
        seats[_seat] = msg.sender;
        // Mark the seat as unavailable by setting its availability to false in the seatAvailability mapping.
        seatAvailability[_seat] = false;
        // Indicate that the sender owns a ticket 
        ownsTicket[msg.sender] = true;


        // refund excess funds paid to the contract
        uint256 consumedGas = startGas - gasleft();
        uint256 gasFees = consumedGas * tx.gasprice;
        uint256 totalCost = newTicket.price + gasFees;
        if (msg.value > totalCost) {
            uint256 refundAmount = msg.value - totalCost;
            (bool success, ) = msg.sender.call{value: refundAmount}("");
            require(success, "Unable to refund excess fees");
        }

        //  emits an event TicketCreated to update others about the successful creation of a new ticket
        emit TicketCreated(ticketId, msg.sender, _seat, price);

        return ticketId;
    }
    
    // function to transfer the ticket to the recipient
    // @return bool true if successful
    function transferTicket(
        address _recipient
    ) public payable returns (bool) {
        // sanity checks
        require(eventDetailsSet, "event details not yet properly set");
        require(seatingPlanSet, "seating plan not yet properly set");
        require(ticketPriceDetailsSet, "ticket details not yet properly set");

        // gets the ticket
        Ticket memory _ticket = tickets[msg.sender];
        // checks if the balance does not exceed the max resale limit
        require(_ticket.transferCount <= _ticket.maxTransferCount, "This ticket cannot be transferred anymore!");

        // check if the cost of transfer is high enough
        // NOTE: once transfer cost is incurred, there will be no refunds, 
        // all transfer cost will go to the contract account
        uint256 transferCost = ticketTransferBaseCost * (2 **( _ticket.transferCount + 1));
        require(msg.value >= transferCost, "Insufficient funds to pay for transfer costs!");

        // check if the sender really owns the ticket
        uint256 ticketId = _ticket.ticketId;
        require(ownerOf(ticketId) == msg.sender, "This ticket is not owned by the sender!");

        // check if the receiver is an EOA account and does not own a ticket
        require(!(_recipient.code.length > 0), "The recipient must be an EOA account!");
        require(!ownsTicket[_recipient], "The recipient already has a ticket!");

        // update the ticket resale property
        _ticket.transferCount = _ticket.transferCount + 1;

        // update world state variables
        delete tickets[msg.sender];
        ownsTicket[msg.sender] = false;

        // transfers the ticket between two parties
        _transfer(msg.sender, _recipient, ticketId);

        // update world state variables
        tickets[_recipient] = _ticket;
        ownsTicket[_recipient] = true;
        seats[_ticket.seat] = _recipient;

        // emit the resale event
        emit TicketTransferred(ticketId, msg.sender, _recipient, _ticket.seat, transferCost);

        return true;
    }

    // function to convert integer to string 
    // @return the converted integer in string format
    function convertIntToStr(uint8 value) private pure returns (string memory) {
        require(value >= 1 && value <= 26, "Invalid input");

        bytes memory buffer = new bytes(1);
        buffer[0] = bytes1(value + 64);

        return string(buffer);
    }

}
