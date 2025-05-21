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
    uint256[] public allProposalIds;

    event ProposalCreated(uint256 indexed proposalId, address indexed proposer, string description);
    event ProposalApproved(uint256 indexed proposalId, address indexed approver);
    event ProposalRejected(uint256 indexed proposalId, address indexed admin);
    event ProposalCanceled(uint256 indexed proposalId, address indexed proposer);
    event ProposalExecuted(uint256 indexed proposalId, address indexed executor);
    event FundsReceived(address indexed sender, uint256 amount);
    event TokensTransferred(address indexed token, address indexed to, uint256 amount);
    event TimelockUpdated(uint256 newTimelock);

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
        _grantRole(EXECUTOR_ROLE, msg.sender);
        _grantRole(PROPOSER_ROLE, msg.sender);
    }

    // Accept ETH
    receive() external payable {
        emit FundsReceived(msg.sender, msg.value);
    }

    fallback() external payable {
        emit FundsReceived(msg.sender, msg.value);
    }

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

        allProposalIds.push(proposalCount);

        emit ProposalCreated(proposalCount, msg.sender, _description);
        return proposalCount;
    }

    function approveProposal(uint256 _proposalId) external onlyRole(ADMIN_ROLE) {
        Proposal storage proposal = proposals[_proposalId];
        require(proposal.id != 0, "Proposal does not exist");
        require(proposal.state == ProposalState.Pending, "Not pending");

        proposal.state = ProposalState.Approved;
        proposal.approvedAt = block.timestamp;

        emit ProposalApproved(_proposalId, msg.sender);
    }

    function rejectProposal(uint256 _proposalId) external onlyRole(ADMIN_ROLE) {
        Proposal storage proposal = proposals[_proposalId];
        require(proposal.state == ProposalState.Pending, "Only pending proposals can be rejected");

        proposal.state = ProposalState.Rejected;

        emit ProposalRejected(_proposalId, msg.sender);
    }

    function cancelProposal(uint256 _proposalId) external {
        Proposal storage proposal = proposals[_proposalId];
        require(proposal.proposer == msg.sender, "Only proposer can cancel");
        require(proposal.state == ProposalState.Pending, "Only pending proposals can be canceled");

        proposal.state = ProposalState.Canceled;

        emit ProposalCanceled(_proposalId, msg.sender);
    }

    function executeProposal(uint256 _proposalId) external onlyRole(EXECUTOR_ROLE) nonReentrant whenNotPaused {
        Proposal storage proposal = proposals[_proposalId];

        require(proposal.id != 0, "Proposal does not exist");
        require(proposal.state == ProposalState.Approved, "Proposal not approved");
        require(block.timestamp >= proposal.approvedAt + executionTimelock, "Timelock not expired");
        require(address(this).balance >= proposal.value, "Insufficient ETH balance");

        proposal.state = ProposalState.Executed;

        (bool success, ) = proposal.target.call{value: proposal.value}(proposal.data);
        require(success, "Execution failed");

        emit ProposalExecuted(_proposalId, msg.sender);
    }

    function transferERC20(address _token, address _to, uint256 _amount) external onlyRole(EXECUTOR_ROLE) nonReentrant whenNotPaused {
        require(_token != address(0), "Invalid token");
        require(_to != address(0), "Invalid recipient");
        require(_amount > 0, "Amount must be > 0");

        IERC20 token = IERC20(_token);
        require(token.balanceOf(address(this)) >= _amount, "Insufficient balance");

        require(token.transfer(_to, _amount), "Transfer failed");
        emit TokensTransferred(_token, _to, _amount);
    }

    function updateTimelock(uint256 _newTimelock) external onlyRole(ADMIN_ROLE) {
        require(_newTimelock >= 1 days, "Timelock too short");
        executionTimelock = _newTimelock;
        emit TimelockUpdated(_newTimelock);
    }

    function getProposal(uint256 _id) external view returns (Proposal memory) {
        return proposals[_id];
    }

    function getAllProposals() external view returns (uint256[] memory) {
        return allProposalIds;
    }

    function pause() external onlyRole(ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(ADMIN_ROLE) {
        _unpause();
    }
}
