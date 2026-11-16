function uav_write_json(path,value)
temporary=[path,'.',num2str(feature('getpid')),'.tmp'];
f=fopen(temporary,'w','n','UTF-8'); assert(f>=0);
fprintf(f,'%s\n',jsonencode(value)); fclose(f);
[ok,message]=movefile(temporary,path,'f'); assert(ok,'%s',message);
end
