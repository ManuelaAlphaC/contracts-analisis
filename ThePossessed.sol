// SPDX-License-Identifier: MIT
// Creator: P4SD Labs

pragma solidity 0.8.15;

import "erc721a/contracts/ERC721A.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/token/common/ERC2981.sol";

error IncorrectSignature();
error SoldOut();
error MaxMinted();
error CallerIsNotOwner();
error CannotSetZeroAddress();
error NonExistentToken();
error CollectionTooSmall();

/**
 * This contract uses a ECDSA signed off-chain to control mint.
 * This way, whether the sale is launched or whether it is pre-sale or public is controlled off-chain.
 * This reduces a lot of on-chain requirements (thus reducing gas fees).
 */
contract ThePossessed is ERC721A, ERC2981, Ownable {
    using Address for address;
    using ECDSA for bytes32;

    uint256 public collectionSize = 10000;
    string public blessedBaseURI;
    string public possessedBaseURI;
    string public preRevealBaseURI;

    mapping(uint256 => bool) private _isPossessed; // verifica se il mitente possiede il token che sta chiamando

    // ECDSA signing address
    address public signingAddress;

    // Sets Treasury Address for withdraw() and ERC2981 royaltyInfo
    address public treasuryAddress;

    constructor(
        address defaultTreasury, // address di chi ricevera i fondi al ritiro
        uint256 defaultCollectionSize, // coencide con "collectionSize" quindi TotalSupply 10.000
        string memory defaultPreRevealBaseURI, // pre reveal metadata uri
        address signer
    ) ERC721A("The Possessed", "PSSSSD") {
        setTreasuryAddress(payable(defaultTreasury)); // il ritiro dei fondi è disponibile solo a 'defaultTreasury'
        setRoyaltyInfo(500); // royalty sono di 5%
        setCollectionSize(defaultCollectionSize); // Total Supply di questa collezione
        setPreRevealBaseURI(defaultPreRevealBaseURI); // metadata uri del nft prima della rivelazione
        setSigningAddress(signer);
    }
    
    function mint(bytes calldata signature, uint256 quantity, uint256 maxMintable) external payable {
        if(!verifySig(msg.sender, maxMintable, msg.value/quantity, signature)) revert IncorrectSignature();
        if(totalSupply() + quantity > collectionSize) revert SoldOut();
        if(_numberMinted(msg.sender) + quantity > maxMintable) revert MaxMinted();

        _mint(msg.sender, quantity);
    }

    // restituisce la quantità di token mintati dal mitente senza dover inserire l'address
    function getMinted() external view returns (uint256) {
        return _numberMinted(msg.sender);
    }

    /**
     * @dev Set the metadata to Possessed or Blessed State
     * se l'utente imposta "isPssssd" su true, verà verificato se il mitente possiede il token 
     * che sta chiamando in qunato esso è memorizzato nella mapping "_isPossessed"
     * in questo modo impostandolo su true combia lo stato dei metadata NFT
     * da blessedBaseURI a possessedBaseURI 
     */
    function setIsPossessed(uint256 tokenID, bool isPssssd) external {
        if (!_exists(tokenID)) revert NonExistentToken();
        if (ownerOf(tokenID) != msg.sender) revert CallerIsNotOwner();
        _isPossessed[tokenID] = isPssssd;
    }

    /**
     * @dev Verify the ECDSA signature
     * l'hash deve essere il risultato di un'operazione di hash affinché la verifica sia sicura
     * Un modo sicuro per garantire ciò è ricevere un hash del messaggio originale
     */
    function verifySig(address sender, uint256 maxMintable, uint256 valueSent, bytes memory signature) internal view returns(bool) {
        bytes32 messageHash = keccak256(abi.encodePacked(sender, maxMintable, valueSent));
        return signingAddress == messageHash.toEthSignedMessageHash().recover(signature);
    }

    // OWNER FUNCTIONS ---------
    function setBaseURIs(string memory blessed, string memory possessed) public onlyOwner {
        blessedBaseURI = blessed;
        possessedBaseURI = possessed;
    }

    /**
     * @dev Nel caso ci sia un bug e dobbiamo aggiornare l'uri
     */
    function setPreRevealBaseURI(string memory newBaseURI) public onlyOwner {
        preRevealBaseURI = newBaseURI;
    }

     /**
     * @dev To decrypt ECDSA sigs or invalidate signed but not claimed tokens
     * questo address decifra le firme, le annula se il mesaggio non è stato firmato 
     * dal titolare della chiave privata
     */
    function setSigningAddress(address newSigningAddress) public onlyOwner {
        if (newSigningAddress == address(0)) revert CannotSetZeroAddress();
        signingAddress = newSigningAddress;
    }
    
    /**
     * @dev Update the royalty percentage (500 = 5%)
     */
    function setRoyaltyInfo(uint96 newRoyaltyPercentage) public onlyOwner {
        _setDefaultRoyalty(treasuryAddress, newRoyaltyPercentage);
    }

    /**
     * @dev Update the royalty wallet address
     */
    function setTreasuryAddress(address payable newAddress) public onlyOwner {
        if (newAddress == address(0)) revert CannotSetZeroAddress();
        treasuryAddress = newAddress;
    }

     /**
     * @dev Useful for unit tests to test minting out logic. No plan to use in production.
     * imposta la quantità massima di token a disposizione ma non deve essere inferiore
     * del prossimo tokenId 
     */
    function setCollectionSize(uint256 size) public onlyOwner {
        if (size < _nextTokenId()) revert CollectionTooSmall();
        collectionSize = size;
    }


    /**
     * @dev Withdraw funds to treasuryAddress
     */    
     function withdraw() external onlyOwner {
        Address.sendValue(payable(treasuryAddress), address(this).balance);
    }

    // OVERRIDES ---------

    /**
     * @dev Variation of {ERC721Metadata-tokenURI}.
     * Returns different token uri depending on blessed or possessed.
     * verifica se l'id dato in imputi esiste quindi è stato già mintato e non supera la TotalSupply
     * alla variabile baseURI viene assegnato lo stato dei metadata del tokenId dato in input
     * viene chiesto se nella mapping "_isPossessed" il i metadata sono di tipo blessedBaseURI 
     * oppure è stato dato il permesso di passare allo stato possessedBaseURI
     * in base alla risposta che viene data la funzione restituirà il baseURI+tokenId 
     * altrimenti se nessuno dei due metadata è stato impostato viene restituito il preRevealBaseURI
     */
    function tokenURI(uint256 tokenID) public view override returns (string memory) {
        require(_exists(tokenID), "ERC721Metadata: URI query for nonexistent token"); 
        string memory baseURI = _isPossessed[tokenID] ? possessedBaseURI : blessedBaseURI;
        return bytes(baseURI).length > 0 ? string(abi.encodePacked(baseURI, _toString(tokenID))) : preRevealBaseURI;
    }


    /**
     * @dev {ERC165-supportsInterface} Adding IERC2981
     */
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721A, ERC2981)
        returns (bool)
    {
        return
            ERC2981.supportsInterface(interfaceId) ||
            super.supportsInterface(interfaceId);
    }

}
