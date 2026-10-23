function fas_write_json(path,value)
temp=[path,'.',num2str(feature('getpid')),'.tmp'];
f=fopen(temp,'w','n','UTF-8'); assert(f>=0,'Cannot create %s',temp);
try
    fprintf(f,'%s\n',jsonencode(value)); fclose(f);
catch err
    fclose(f); rethrow(err);
end
[ok,message]=movefile(temp,path,'f'); assert(ok,'%s',message);
end
