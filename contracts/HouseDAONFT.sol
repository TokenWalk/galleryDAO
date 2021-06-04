// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC721/IERC721.sol';
import '@openzeppelin/contracts/utils/math/SafeMath.sol';
import './interfaces/IHouseDAO.sol';

contract HouseDAONFT is IHouseDAO {
	using SafeMath for uint;

    string public name;

    mapping(address => Member) public members;
    mapping(uint => Proposal) public proposals;
    // use shares on member struct for balances
    uint public totalProposalCount = 0;
    uint public memberCount = 0;
    uint public proposalTime;
    uint public gracePeriod = 3 days;

    uint public balance;
    uint public nextNFTId;
    uint public tokenOwner;
    uint public issuanceSupply;

    uint public threshold;
    uint public nftPrice;
    uint public totalGovernanceSupply;
    uint public minimumProposalAmount;

    address public tokenVault;
    address public ERC721Address;
    address public WETH = address(0);

    modifier onlyMember {
        require(members[msg.sender].roles.member == true, "not a member");
        _;
    }

    modifier onlyHeadOfHouse {
        require(members[msg.sender].roles.headOfHouse == true, "not a head of house");
        _;
    }

    modifier isPassed(uint _proposalId) {
        require(proposals[_proposalId].canceled == false, "proposal was canceled");
        require(proposals[_proposalId].executed == false, "proposal already executed");
        require(proposals[_proposalId].yesVotes >= threshold, "change role does not meet vote threshold");
        require(proposals[_proposalId].yesVotes >= proposals[_proposalId].noVotes, "no votes outweigh yes");
        _;
    }

    constructor(
        address[] memory heads,
        address _ERC721Address,
        address _tokenVault,
        uint _tokenIdStartIndex, // tokens issued must be owned in a contiguous sequence
        uint _proposalTime,
        uint _totalGovernanceSupply,
        uint _threshold,
        uint _minimumProposalAmount,
        uint _issuanceSupply,
        address _weth,
        uint _price
    ) {
        for(uint i=0; i<heads.length; i++) {
            // create head of house member struct
            require(heads[i] != address(0));
            members[heads[i]].roles.headOfHouse = true;
            members[heads[i]].roles.member = true;
            memberCount++;
        }

        ERC721Address = _ERC721Address;
        proposalTime = _proposalTime * 1 days;
        threshold = _threshold;
        totalGovernanceSupply = _totalGovernanceSupply;
        minimumProposalAmount = _minimumProposalAmount;
        WETH = _weth;
        nftPrice = _price;
        tokenVault = _tokenVault;
        nextNFTId = _tokenIdStartIndex;
        issuanceSupply = _issuanceSupply;
        // entrynumber
    }

	function nftMembershipEntry() public {
		// put an entry number here
		require(members[msg.sender].roles.member == false);
		require(ERC721Address != address(0));
		require(IERC721(ERC721Address).balanceOf(msg.sender) >= 1);
		members[msg.sender].roles.member = true;
	}

	function contribute() public {
		require(issuanceSupply > 0, "there are no more tokens to issue");
		require(IERC721(ERC721Address).balanceOf(address(this)) >= 1, "there are not enough tokens left for entry");
        require(IERC20(WETH).balanceOf(msg.sender) >= nftPrice, "sender does not have enough weth for nft");
        require(members[msg.sender].roles.member = false, "contributor is already a member");
        members[msg.sender].roles.member = true;
        memberCount++;
        nextNFTId++;
        issuanceSupply--;
        IERC20(WETH).transferFrom(msg.sender, address(this), nftPrice);
    	IERC721(ERC721Address).transferFrom(tokenVault, msg.sender, nextNFTId);
	}

	// this is non refundable
	function fundDAO(uint _amount) public {
		require(_amount > 0);
		require(IERC20(WETH).balanceOf(msg.sender) >= _amount);
		balance += _amount;
		IERC20(WETH).transferFrom(msg.sender, address(this), _amount);
	}

	// make nft and erc20 version different contracts
	function headOfhouseChangeERC721(address _entryToken) onlyHeadOfHouse public {
		require(_entryToken != address(0));
		ERC721Address = _entryToken;
	}

	// make nft and erc20 version different contracts
	function headOfhouseIncreaseERC721Supply(uint _amount, uint _tokenIdStartIndex) onlyHeadOfHouse public {
		require(_amount > 0, "increase totalSupply to issue must be greater than 0");
		require(_tokenIdStartIndex > nextNFTId, "start index is not past last nft id issued, issue the remaining ids");
		issuanceSupply += _amount;
		nextNFTId = _tokenIdStartIndex;
	}

    function vote(uint _proposalId, bool _vote) onlyMember public {
        require(proposals[_proposalId].hasVoted[msg.sender] == false, "already voted");
        require(proposals[_proposalId].canceled == false, "proposal has been canceled");
        require(proposals[_proposalId].executed == false, "proposal is already executed");
        require(proposals[_proposalId].deadline >= block.timestamp, "proposal is past the deadline");

        proposals[_proposalId].hasVoted[msg.sender] = true;

        if(_vote == false){
            proposals[_proposalId].noVotes += IERC721(ERC721Address).balanceOf(msg.sender);
        } else {
            proposals[_proposalId].yesVotes += IERC721(ERC721Address).balanceOf(msg.sender);
        }
    }

    // change role, commission art, request funcing
    function submitProposal(Role memory _role, address _recipient, uint _funding, uint8 _proposalType) onlyMember public {
        require(balance >= _funding, "more funds are request than the DAO currently has");
        require(IERC721(ERC721Address).balanceOf(msg.sender) >= minimumProposalAmount, "submit proposal does not have enough gov tokens");
        
        proposals[totalProposalCount].fundsRequested = _funding;
        proposals[totalProposalCount].role = _role;
        proposals[totalProposalCount].proposalType = _proposalType; // 0 = funding proposal // 1 = change role // 2 = entry
        proposals[totalProposalCount].yesVotes = IERC721(ERC721Address).balanceOf(msg.sender);    
        proposals[totalProposalCount].deadline = block.timestamp + proposalTime;
        proposals[totalProposalCount].proposer = msg.sender;
        proposals[totalProposalCount].targetAddress = _recipient; // can switch target to contract and provide call data
        proposals[totalProposalCount].hasVoted[msg.sender] = true;

        totalProposalCount++;
    }

    // Execute proposals
    // todo: maybe check if over threshold on every vote, if so start grace period
    function startFundingProposalGracePeriod(uint _proposalId) isPassed(_proposalId) external {
        require(proposals[_proposalId].proposalType == 0, "proposal is not a funding type");
        require(proposals[_proposalId].gracePeriod == 0, "proposal already entered grace period");
		
        proposals[_proposalId].gracePeriod = block.timestamp + gracePeriod;
    }

    function executeFundingProposal(uint _proposalId) isPassed(_proposalId) external {
        require(balance >= proposals[_proposalId].fundsRequested, "not enough funds on the DAO to finalize");
        require(block.timestamp >= proposals[_proposalId].gracePeriod, "grace period has not elapsed");

        balance = balance.sub(proposals[_proposalId].fundsRequested);
        proposals[_proposalId].executed = true;
        require(IERC20(WETH).transferFrom(address(this), proposals[_proposalId].targetAddress, proposals[_proposalId].fundsRequested));
    }

    //TODO: combine common requires to a modifier
    function executeChangeRoleProposal(uint _proposalId) isPassed(_proposalId) external {
        require(proposals[_proposalId].proposalType == 1, "proposal is not change role type");

        members[proposals[_proposalId].targetAddress].roles = proposals[_proposalId].role;
        proposals[_proposalId].executed = true;
    }

    function cancelProposal(uint _proposalId) public {
        require(proposals[_proposalId].canceled == false);
        require(proposals[_proposalId].executed == false);
        require(proposals[_proposalId].deadline >= block.timestamp);
        require(proposals[_proposalId].proposer == msg.sender);
        proposals[_proposalId].canceled = true;
    }
}