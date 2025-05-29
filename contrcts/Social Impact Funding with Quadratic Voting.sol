// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

/**
 * @title Social Impact Funding with Quadratic Voting
 * @dev A decentralized platform for funding social causes using quadratic voting mechanism
 * @author Social Impact DAO
 */
contract Project is ReentrancyGuard, Ownable {
    using Math for uint256;

    struct SocialProject {
        uint256 id;
        string title;
        string description;
        address payable beneficiary;
        uint256 fundingGoal;
        uint256 totalFunding;
        uint256 votingPower;
        uint256 deadline;
        bool isActive;
        bool fundsWithdrawn;
    }

    struct Vote {
        uint256 projectId;
        uint256 amount;
        uint256 votes;
    }

    // State variables
    mapping(uint256 => SocialProject) public projects;
    mapping(address => mapping(uint256 => Vote)) public userVotes;
    mapping(address => uint256) public userContributions;
    
    uint256 public projectCounter;
    uint256 public totalPoolFunds;
    uint256 public constant MINIMUM_CONTRIBUTION = 0.001 ether;
    uint256 public constant VOTING_PERIOD = 7 days;
    
    // Events
    event ProjectCreated(uint256 indexed projectId, string title, address beneficiary, uint256 fundingGoal);
    event VoteCast(address indexed voter, uint256 indexed projectId, uint256 amount, uint256 votes);
    event FundsAllocated(uint256 indexed projectId, uint256 amount);
    event FundsWithdrawn(uint256 indexed projectId, uint256 amount);

    constructor() Ownable(msg.sender) {}

    /**
     * @dev Core Function 1: Create a new social impact project
     * @param _title Project title
     * @param _description Project description
     * @param _beneficiary Address that will receive funds if project is funded
     * @param _fundingGoal Target funding amount in wei
     */
    function createProject(
        string memory _title,
        string memory _description,
        address payable _beneficiary,
        uint256 _fundingGoal
    ) external {
        require(bytes(_title).length > 0, "Title cannot be empty");
        require(bytes(_description).length > 0, "Description cannot be empty");
        require(_beneficiary != address(0), "Invalid beneficiary address");
        require(_fundingGoal > 0, "Funding goal must be greater than 0");

        projectCounter++;
        
        projects[projectCounter] = SocialProject({
            id: projectCounter,
            title: _title,
            description: _description,
            beneficiary: _beneficiary,
            fundingGoal: _fundingGoal,
            totalFunding: 0,
            votingPower: 0,
            deadline: block.timestamp + VOTING_PERIOD,
            isActive: true,
            fundsWithdrawn: false
        });

        emit ProjectCreated(projectCounter, _title, _beneficiary, _fundingGoal);
    }

    /**
     * @dev Core Function 2: Cast quadratic vote for a project
     * @param _projectId ID of the project to vote for
     * Quadratic voting: cost = votes^2, voting power = sqrt(contribution)
     */
    function castQuadraticVote(uint256 _projectId) external payable nonReentrant {
        require(_projectId > 0 && _projectId <= projectCounter, "Invalid project ID");
        require(msg.value >= MINIMUM_CONTRIBUTION, "Contribution below minimum");
        
        SocialProject storage project = projects[_projectId];
        require(project.isActive, "Project is not active");
        require(block.timestamp <= project.deadline, "Voting period has ended");

        // Calculate quadratic voting power: voting power = sqrt(contribution)
        uint256 newVotes = Math.sqrt(msg.value);
        
        // Update user's vote for this project
        Vote storage userVote = userVotes[msg.sender][_projectId];
        userVote.projectId = _projectId;
        userVote.amount += msg.value;
        userVote.votes = Math.sqrt(userVote.amount); // Recalculate total votes

        // Update project voting power and funding
        project.votingPower = project.votingPower - Math.sqrt(userVote.amount - msg.value) + userVote.votes;
        project.totalFunding += msg.value;
        
        // Update user's total contributions
        userContributions[msg.sender] += msg.value;
        totalPoolFunds += msg.value;

        emit VoteCast(msg.sender, _projectId, msg.value, newVotes);
    }

    /**
     * @dev Core Function 3: Distribute funds based on quadratic voting results
     * Can be called after voting period ends
     */
    function distributeFunds() external nonReentrant {
        require(totalPoolFunds > 0, "No funds to distribute");
        
        uint256 totalVotingPower = 0;
        uint256 activeProjects = 0;
        
        // Calculate total voting power across all active projects
        for (uint256 i = 1; i <= projectCounter; i++) {
            if (projects[i].isActive && block.timestamp > projects[i].deadline) {
                totalVotingPower += projects[i].votingPower;
                activeProjects++;
            }
        }
        
        require(activeProjects > 0, "No projects ready for fund distribution");
        require(totalVotingPower > 0, "No votes cast");

        // Distribute funds proportionally based on quadratic voting power
        for (uint256 i = 1; i <= projectCounter; i++) {
            SocialProject storage project = projects[i];
            
            if (project.isActive && block.timestamp > project.deadline && !project.fundsWithdrawn) {
                uint256 allocation = (totalPoolFunds * project.votingPower) / totalVotingPower;
                
                if (allocation > 0) {
                    project.fundsWithdrawn = true;
                    project.isActive = false;
                    
                    // Transfer allocated funds to project beneficiary
                    (bool success, ) = project.beneficiary.call{value: allocation}("");
                    require(success, "Fund transfer failed");
                    
                    emit FundsAllocated(i, allocation);
                    emit FundsWithdrawn(i, allocation);
                }
            }
        }
        
        // Reset total pool funds after distribution
        totalPoolFunds = 0;
    }

    // View functions
    function getProject(uint256 _projectId) external view returns (SocialProject memory) {
        require(_projectId > 0 && _projectId <= projectCounter, "Invalid project ID");
        return projects[_projectId];
    }

    function getUserVote(address _user, uint256 _projectId) external view returns (Vote memory) {
        return userVotes[_user][_projectId];
    }

    function getActiveProjects() external view returns (uint256[] memory) {
        uint256[] memory activeProjectIds = new uint256[](projectCounter);
        uint256 count = 0;
        
        for (uint256 i = 1; i <= projectCounter; i++) {
            if (projects[i].isActive) {
                activeProjectIds[count] = i;
                count++;
            }
        }
        
        // Resize array to actual count
        uint256[] memory result = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            result[i] = activeProjectIds[i];
        }
        
        return result;
    }

    // Emergency functions
    function pauseProject(uint256 _projectId) external onlyOwner {
        require(_projectId > 0 && _projectId <= projectCounter, "Invalid project ID");
        projects[_projectId].isActive = false;
    }

    function emergencyWithdraw() external onlyOwner {
        payable(owner()).transfer(address(this).balance);
    }

    receive() external payable {
        totalPoolFunds += msg.value;
    }
}
