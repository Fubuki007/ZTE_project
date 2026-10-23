function value=fas_hash(bytes)
md=java.security.MessageDigest.getInstance('SHA-256');
md.update(uint8(bytes)); value=lower(reshape(dec2hex(typecast(md.digest(),'uint8'),2).',1,[]));
end
