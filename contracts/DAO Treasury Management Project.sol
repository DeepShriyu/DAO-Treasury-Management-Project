// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

/**
 * @title DAOTreasury
 * @dev Main contract for managing DAO treasury funds with governance controls
 */
contract DAOTreasury is AccessControl, ReentrancyGuard, Pausable {
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant EXECUTOR_ROLE = keccak256("EXECUTOR_ROLE");
    bytes32 public constant PROPOSER_ROLE = keccak256("PROPOSER_ROLE");
    
    uint256 public proposalCount;
    uint256 public executionTimelock = 2 days;
    
    enum ProposalState { Pending, Approved, Executed, Rejected, Canceled }
    
    struct Proposal {
        uint256 id;
        address proposer;
        address target;
        uint256 value;
        bytes data;
        string description;
        uint256 createdAt;
        uint256 approvedAt;
        ProposalState state;
    }
    
    mapping(uint256 => Proposal) public proposals;
    
    event ProposalCreated(uint256 indexed proposalId, address indexed proposer, string description);
    event ProposalApproved(uint256 indexed proposalId, address indexed approver);
    event ProposalExecuted(uint256 indexed proposalId, address indexed executor);
    event FundsReceived(address indexed sender, uint256 amount);
    event TokensTransferred(address indexed token, address indexed to, uint256 amount);
    
    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
        _grantRole(EXECUTOR_ROLE, msg.sender);
        _grantRole(PROPOSER_ROLE, msg.sender);
    }
    
    // Allow the treasury to receive ETH
    receive() external payable {
        emit FundsReceived(msg.sender, msg.value);
    }
    
    /**
     * @dev Creates a new treasury proposal
     * @param _target The address that will receive funds or be called
     * @param _value The amount of ETH to send
     * @param _data The calldata to send if this is a contract call
     * @param _description Human-readable description of the proposal
     * @return The ID of the created proposal
     */
    function createProposal(
        address _target, 
        uint256 _value, 
        bytes memory _data, 
        string memory _description
    ) external onlyRole(PROPOSER_ROLE) returns (uint256) {
        require(_target != address(0), "Invalid target address");
        require(bytes(_description).length > 0, "Description required");
        
        proposalCount++;
        
        Proposal storage proposal = proposals[proposalCount];
        proposal.id = proposalCount;
        proposal.proposer = msg.sender;
        proposal.target = _target;
        proposal.value = _value;
        proposal.data = _data;
        proposal.description = _description;
        proposal.createdAt = block.timestamp;
        proposal.state = ProposalState.Pending;
        
        emit ProposalCreated(proposalCount, msg.sender, _description);
        return proposalCount;
    }
    
    /**
     * @dev Approves a pending proposal
     * @param _proposalId The ID of the proposal to approve
     */
    function approveProposal(uint256 _proposalId) external onlyRole(ADMIN_ROLE) {
        Proposal storage proposal = proposals[_proposalId];
        require(proposal.id != 0, "Proposal does not exist");
        require(proposal.state == ProposalState.Pending, "Not in pending state");
        
        proposal.state = ProposalState.Approved;
        proposal.approvedAt = block.timestamp;
        
        emit ProposalApproved(_proposalId, msg.sender);
    }
    
    /**
     * @dev Executes an approved proposal after timelock period
     * @param _proposalId The ID of the proposal to execute
     */
    function executeProposal(uint256 _proposalId) external onlyRole(EXECUTOR_ROLE) nonReentrant whenNotPaused {
        Proposal storage proposal = proposals[_proposalId];
        
        require(proposal.id != 0, "Proposal does not exist");
        require(proposal.state == ProposalState.Approved, "Not approved");
        require(block.timestamp >= proposal.approvedAt + executionTimelock, "Timelock not expired");
        require(address(this).balance >= proposal.value, "Insufficient balance");
        
        proposal.state = ProposalState.Executed;
        
        // Execute the proposal
        (bool success, ) = proposal.target.call{value: proposal.value}(proposal.data);
        require(success, "Transaction execution failed");
        
        emit ProposalExecuted(_proposalId, msg.sender);
    }
    
    /**
     * @dev Transfers ERC20 tokens from the treasury
     * @param _token The ERC20 token address
     * @param _to The recipient address
     * @param _amount The amount to transfer
     */
    function transferERC20(address _token, address _to, uint256 _amount) external onlyRole(EXECUTOR_ROLE) nonReentrant whenNotPaused {
        require(_token != address(0), "Invalid token address");
        require(_to != address(0), "Invalid recipient address");
        require(_amount > 0, "Amount must be greater than 0");
        
        IERC20 token = IERC20(_token);
        require(token.balanceOf(address(this)) >= _amount, "Insufficient token balance");
        
        require(token.transfer(_to, _amount), "Token transfer failed");
        emit TokensTransferred(_token, _to, _amount);
    }
    
    /**
     * @dev Pauses all proposal executions and token transfers
     */
    function pause() external onlyRole(ADMIN_ROLE) {
        _pause();
    }
    
    /**
     * @dev Unpauses the contract
     */
    function unpause() external onlyRole(ADMIN_ROLE) {
        _unpause();
    }
}
