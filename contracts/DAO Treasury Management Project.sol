// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
\
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant EXECUTOR_ROLE = keccak256("EXECUTOR_ROLE");
    bytes32 public constant PROPOSER_ROLE = keccak256("PROPOSER_ROLE")

    uint256 public proposalCoun
    uint256 public executionTimelock = 2 days;
    uint256 public proposalExpiry 


    struct Proposal {
        uint256
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
    bytes32[] public executionHistory;

    event ProposalCreated(uint256 indexed proposalId, address indexed proposer, string description);
    event ProposalApproved(uint256 indexed proposalId, address indexed approver);
    event ProposalRejected(uint256 indexed proposalId, address indexed admin);
    event ProposalCanceled(uint256 indexed proposalId, address indexed proposer);
    event ProposalExecuted(uint256 indexed proposalId, address indexed executor);
    event FundsReceived(address indexed sender, uint256 amount);
    event TokensTransferred(address indexed token, address indexed to, uint256 amount);
    event TimelockUpdated(uint256 newTimelock);
    event ProposalUpdated(uint256 indexed proposalId, string newDescription);
    event EmergencyWithdrawal(address to, uint256 amount);

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender)
        _grantRole(EXECUTOR_ROLE, msg.sender);
        _grantRole(PROPOSER_ROLE, msg.sender);
    }

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
        proposals[proposalCount] = Proposal({
            id: proposalCount,
            proposer: msg.sender,
            target: _target,
            value: _value,
            data: _data,
            description: _description,
            createdAt: block.timestamp,
            approvedAt: 0,
            state: ProposalState.Pending
        });

        allProposalIds.push(proposalCount);
        emit ProposalCreated(proposalCount, msg.sender, _description);
        return proposalCount;
    }

    function approveProposal(uint256 _proposalId) external onlyRole(ADMIN_ROLE) {
        Proposal storage proposal = proposals[_proposalId];
        require(proposal.state == ProposalState.Pending, "Not pending");
        require(block.timestamp <= proposal.createdAt + proposalExpiry, "Proposal expired");

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
 event ProposalCreated(uint256 indexed proposalId, address indexed proposer, string description);
    event ProposalApproved(uint256 indexed proposalId, address indexed approver);
    event ProposalRejected(uint256 indexed proposalId, address indexed admin);
    event ProposalCanceled(uint256 indexed proposalId, address indexed proposer);
    event ProposalExecuted(uint256 indexed proposalId, address indexed executor);
    event FundsReceived(address indexed sender, uint256 amount);
    event TokensTransferred(address indexed token, address indexed to, uint256 amount);
    event TimelockUpdated(uint256 newTimelock);
    event ProposalUpdated(uint256 indexed proposalId, string newDescription);
    event EmergencyWithdrawal(address to, uint256 amount);
    function cancelProposal(uint256 _proposalId) external {
        Proposal storage proposal = proposals[_proposalId];
        require(proposal.proposer == msg.sender, "Only proposer can cancel");
        require(proposal.state == ProposalState.Pending, "Only pending proposals can be canceled");

        proposal.state = ProposalState.Canceled;

        emit ProposalCanceled(_proposalId, msg.sender);
    }

    function updateProposalDescription(uint256 _proposalId, string memory newDescription) external {
        Proposal storage proposal = proposals[_proposalId];
        require(proposal.proposer == msg.sender, "Not proposer");
        require(proposal.state == ProposalState.Pending, "Only pending proposals can be updated");
        require(bytes(newDescription).length > 0, "Empty description");

        proposal.description = newDescription;
        emit ProposalUpdated(_proposalId, newDescription);
    }

    function executeProposal(uint256 _proposalId) external onlyRole(EXECUTOR_ROLE) nonReentrant whenNotPaused {
        Proposal storage proposal = proposals[_proposalId];

        require(proposal.state == ProposalState.Approved, "Proposal not approved");
        require(block.timestamp >= proposal.approvedAt + executionTimelock, "Timelock not expired");
        require(address(this).balance >= proposal.value, "Insufficient ETH balance");

        proposal.state = ProposalState.Executed;

        (bool success, ) = proposal.target.call{value: proposal.value}(proposal.data);
        require(success, "Execution failed");

        executionHistory.push(keccak256(abi.encodePacked(_proposalId, block.timestamp)));

        emit ProposalExecuted(_proposalId, msg.sender);
    }

    function transferERC20(address _token, address _to, uint256 _amount) external onlyRole(EXECUTOR_ROLE) nonReentrant whenNotPaused {
        require(_token != address(0) && _to != address(0), "Invalid address");
        require(_amount > 0, "Amount must be > 0");

        IERC20 token = IERC20(_token);
        require(token.balanceOf(address(this)) >= _amount, "Insufficient balance");

        require(token.transfer(_to, _amount), "Transfer failed");
        emit TokensTransferred(_token, _to, _amount);
    }

    function emergencyWithdrawETH(address payable _to, uint256 _amount) external onlyRole(ADMIN_ROLE) {
        require(_to != address(0), "Invalid address");
        require(address(this).balance >= _amount, "Not enough ETH");

        _to.transfer(_amount);
        emit EmergencyWithdrawal(_to, _amount);
    }

    function updateTimelock(uint256 _newTimelock) external onlyRole(ADMIN_ROLE) {
        require(_newTimelock >= 1 days, "Too short");
        executionTimelock = _newTimelock;
        emit TimelockUpdated(_newTimelock);
    }

    function getProposal(uint256 _id) external view returns (Proposal memory) {
        return proposals[_id];
    }

    function getAllProposals() external view returns (uint256[] memory) {
        return allProposalIds;
    }

    function getExecutionHistory() external view returns (bytes32[] memory) {
        return executionHistory;
    }

    function getActiveProposals() external view returns (uint256[] memory activeIds) {
        uint256 count;
        for (uint256 i = 0; i < allProposalIds.length; i++) {
            if (proposals[allProposalIds[i]].state == ProposalState.Pending) {
                count++;
            }
        }

        activeIds = new uint256[](count);
        uint256 index;
        for (uint256 i = 0; i < allProposalIds.length; i++) {
            if (proposals[allProposalIds[i]].state == ProposalState.Pending) {
                activeIds[index++] = allProposalIds[i];
            }
        }
    }

    function pause() external onlyRole(ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(ADMIN_ROLE) {
        _unpause();
    }
}
