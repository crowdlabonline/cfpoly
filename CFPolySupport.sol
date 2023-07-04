// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;


import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Supply.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/common/ERC2981.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

/// @custom:security-contact security@btcgnal.ai
contract CFPolySupport is
ERC1155,
Ownable,
Pausable,
ERC1155Supply,
ERC2981,
ReentrancyGuard
{
    constructor() ERC1155("")
    {
        _royaltiesRecipient = msg.sender;
    }

    uint256 private constant PREMIUM_SUPPORTERS = 300;
    uint256 premiumTokenId = 1;
    uint256 regularTokenId = 1;

    address _royaltiesRecipient;
    string public name = "CFPoly.io Supporter Badges";
    string public symbol = "CFPSB";

    function setURI(string memory newUri) external onlyOwner
    {
        _setURI(newUri);
    }

    function contractURI() external view returns (string memory)
    {
        return string.concat(super.uri(0), "CFPSB.json");
    }

    function tokenURI(uint256 tokenId) public view returns (string memory)
    {
        string memory _URI = (tokenId >= (1 << 128)) ? string.concat(super.uri(0), Strings.toString(tokenId), ".json") :
        (tokenId < (10000 << 64))? string.concat(super.uri(0), Strings.toString(tokenId), ".json") : string.concat(super.uri(0), "badge.json");
        return _URI;
    }

    function uri(uint256 tokenId) public view virtual override returns (string memory)
    {
        if(0 == tokenId)
            return super.uri(0);
        return tokenURI(tokenId);
    }

    function withdrawFunds() external onlyOwner
    {
        require(address(this).balance > 0, "Nothing to withdraw");
        payable(_royaltiesRecipient).transfer(address(this).balance);
    }

    function getBalance() public onlyOwner view returns (uint256)
    {
        return address(this).balance;
    }

    function premiumTokensAvailable() public view returns(uint256)
    {
        return PREMIUM_SUPPORTERS - premiumTokenId + 1;
    }

    event PremiumSupporterBadgeIssued(address indexed to, uint256 indexed amount, uint256 indexed tid, uint timestamp);
    function premiumSupport() payable public whenNotPaused
    {
        require(msg.value >= 30000000000000000000, "Premium token is at least 30 MATIC");
        require(premiumTokenId <= PREMIUM_SUPPORTERS, "No premium badges available");

        _mint(msg.sender, premiumTokenId << 128, 1, "");
        emit PremiumSupporterBadgeIssued(msg.sender, msg.value, premiumTokenId << 128, block.timestamp);
        premiumTokenId++;
    }

    function mintPremium() onlyOwner public
    {
        require(premiumTokenId <= PREMIUM_SUPPORTERS, "No premium badges available");
        _mint(owner(), premiumTokenId << 128, 1, "");
        premiumTokenId++;
    }

    event SupporterBadgeIssued(address indexed to, uint256 indexed amount, uint256 indexed tid, uint timestamp);
    function support() payable public whenNotPaused
    {
        require(msg.value > 0, "Can't mint a badge for 0");
        _mint(msg.sender, regularTokenId << 64, 1, "");
        emit SupporterBadgeIssued(msg.sender, msg.value, regularTokenId << 64, block.timestamp);
        regularTokenId++;
    }

    function mintRegular() onlyOwner public
    {
        _mint(owner(), regularTokenId << 64, 1, "");
        regularTokenId++;
    }


    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    function _beforeTokenTransfer(address operator, address from, address to, uint256[] memory ids, uint256[] memory amounts, bytes memory data)
    internal
    whenNotPaused
    override(ERC1155, ERC1155Supply)
    {
        super._beforeTokenTransfer(operator, from, to, ids, amounts, data);
    }

    event Received(address, uint256);
    receive() external payable
    {
        emit Received(msg.sender, msg.value);
    }

    event FallBack(address, uint256);
    fallback() external payable
    {
        emit FallBack(msg.sender, msg.value);
    }


    function _setRoyaltiesRecipient(address newRecipient) private
    {
        require(newRecipient != address(0), "Can't use NULL address");
        _royaltiesRecipient = newRecipient;
    }

    function setRoyaltiesRecipient(address newRecipient) external onlyOwner
    {
        _setRoyaltiesRecipient(newRecipient);
    }

    function royaltyInfo(uint256 _tokenId, uint256 _salePrice) public view override returns (address recipient, uint256 amount)
    {
        uint256 percent = 600;
        if (_tokenId >= (1 << 128))
            percent = 1000;

        return (_royaltiesRecipient, (_salePrice * percent) / 10000);
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC1155, ERC2981) returns (bool)
    {
        return (interfaceId == type(IERC2981).interfaceId || super.supportsInterface(interfaceId));
    }
}