// SPDX-License-Identifier: MIT
pragma solidity >=0.7.0 <0.9.0;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract AgencyWolfBillionaireClub is ERC721Enumerable, Ownable {
    using Strings for uint256;
    string private baseURI;
    string public baseExtension = ".json";
    string public notRevealedUri;
    uint256 public cost = 100000 ether;
    uint256 public maxSupply = 10000;
    uint256 public maxMintAmount = 20;
    uint256 public nftPerAddressLimit = 100;
    uint256 public publicSaleDate = 1635814800;
    address public stakingAddress;
    bool public paused = false;
    bool public revealed = false;
    mapping (address => bool) whitelistedAddresses;
    mapping (address => uint256) public addressMintedBalance;
    mapping (uint => address) public tokenOwner;
    mapping (uint => uint) public stakedInTime;
    mapping (uint => uint) public stakeTime;

    // Contracts
    IERC20 public paymentsToken;

    constructor(string memory _name, string memory _symbol, string memory _initNotRevealedUri, address _paymentsToken) ERC721(_name, _symbol) {
        paymentsToken = IERC20(_paymentsToken);
        setNotRevealedURI(_initNotRevealedUri);
    }

    //MODIFIERS
    modifier notPaused {
         require(!paused, "the contract is paused");
         _;
    }

    modifier saleStarted {
        require(block.timestamp >= publicSaleDate, "Sale has not started yet");
        _;
    }

    modifier minimumMintAmount(uint256 _mintAmount) {
        require(_mintAmount > 0, "need to mint at least 1 NFT");
        _;
    }

    // INTERNAL
    function _baseURI() internal view virtual override returns (string memory) {
        return baseURI;
    }

    function publicsaleValidations(uint256 _ownerMintedCount, uint256 _mintAmount) internal view {
        require(_ownerMintedCount + _mintAmount <= nftPerAddressLimit,"max NFT per address exceeded");
        require(_mintAmount <= maxMintAmount,"max mint amount per transaction exceeded");
    }

    //MINT
    function mint(uint256 _mintAmount) public notPaused saleStarted minimumMintAmount(_mintAmount) {
        uint256 supply = totalSupply();
        uint256 ownerMintedCount = addressMintedBalance[msg.sender];

        //Do some validations depending on which step of the sale we are in
        publicsaleValidations(ownerMintedCount, _mintAmount);

        require(supply + _mintAmount <= maxSupply, "max NFT limit exceeded");

        paymentsToken.transferFrom(msg.sender, address(this), cost * _mintAmount);

        for (uint256 i = 1; i <= _mintAmount; i++) {
            addressMintedBalance[msg.sender]++;
            _safeMint(msg.sender, supply + i);
        }
    }

    function gift(uint256 _mintAmount, address destination) public onlyOwner {
        require(_mintAmount > 0, "need to mint at least 1 NFT");
        uint256 supply = totalSupply();
        require(supply + _mintAmount <= maxSupply, "max NFT limit exceeded");

        for (uint256 i = 1; i <= _mintAmount; i++) {
            addressMintedBalance[destination]++;
            _safeMint(destination, supply + i);
        }
    }

    function updateStakeTime(uint tokenId, bool isStake) public {
        require(msg.sender == stakingAddress);

        if (isStake) {
            stakeTime[tokenId] = block.timestamp;
        } else {
            stakedInTime[tokenId] = stakedInTime[tokenId] + block.timestamp - stakeTime[tokenId];
        }
    }

    function getTokenOwner(uint tokenId) public view returns(address) {
        return tokenOwner[tokenId];
    }

    function _transfer(
        address from,
        address to,
        uint tokenId
    ) internal override {
        if (to != stakingAddress && to != tokenOwner[tokenId]) {
            tokenOwner[tokenId] = to;
        }

        super._transfer(from, to, tokenId);
    }

    //PUBLIC VIEWS
    function isWhitelisted(address _user) public view returns (bool) {
        return whitelistedAddresses[_user];
    }

    function walletOfOwner(address _owner) public view returns (uint256[] memory) {
        uint256 ownerTokenCount = balanceOf(_owner);
        uint256[] memory tokenIds = new uint256[](ownerTokenCount);
        for (uint256 i; i < ownerTokenCount; i++) {
            tokenIds[i] = tokenOfOwnerByIndex(_owner, i);
        }
        return tokenIds;
    }

    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        require(_exists(tokenId), "ERC721Metadata: URI query for nonexistent token");

        if (!revealed) {
            return notRevealedUri;
        } else {
            string memory currentBaseURI = _baseURI();
            return bytes(currentBaseURI).length > 0 ? string(abi.encodePacked(currentBaseURI,tokenId.toString(), baseExtension)) : "";
        }
    }

    function getCurrentCost() public view returns (uint256) {
        return cost;
    }

    //ONLY OWNER VIEWS
    function getBaseURI() public view onlyOwner returns (string memory) {
        return baseURI;
    }

    function getContractBalance() public view onlyOwner returns (uint256) {
        return address(this).balance;
    }

    //ONLY OWNER SETTERS
    function reveal() public onlyOwner {
        revealed = true;
    }

    function pause(bool _state) public onlyOwner {
        paused = _state;
    }

    function setNftPerAddressLimit(uint256 _limit) public onlyOwner {
        nftPerAddressLimit = _limit;
    }

    function setCost(uint256 _newCost) public onlyOwner {
        cost = _newCost;
    }

    function setStakingAddress(address _address) public onlyOwner {
        stakingAddress = _address;
    }

    function setmaxMintAmount(uint256 _newmaxMintAmount) public onlyOwner {
        maxMintAmount = _newmaxMintAmount;
    }

    function setBaseURI(string memory _newBaseURI) public onlyOwner {
        baseURI = _newBaseURI;
    }

    function setBaseExtension(string memory _newBaseExtension) public onlyOwner {
        baseExtension = _newBaseExtension;
    }

    function setNotRevealedURI(string memory _notRevealedURI) public onlyOwner {
        notRevealedUri = _notRevealedURI;
    }

    function setMaxSupply(uint256 _maxSupply) public onlyOwner {
        maxSupply = _maxSupply;
    }

    function setPublicSaleDate(uint256 _publicSaleDate) public onlyOwner {
        publicSaleDate = _publicSaleDate;
    }

    function whitelistUsers(address[] memory addresses) public onlyOwner {
        for (uint256 i = 0; i < addresses.length; i++) {
            whitelistedAddresses[addresses[i]] = true;
        }
    }

    function withdraw() public payable onlyOwner {
        uint balance = paymentsToken.balanceOf(address(this));
        require(balance > 0);
        paymentsToken.transfer(msg.sender, balance);
    }
}