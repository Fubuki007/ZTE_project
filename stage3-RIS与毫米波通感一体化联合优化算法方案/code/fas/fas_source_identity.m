function identity=fas_source_identity()
code=fileparts(fileparts(mfilename('fullpath')));
files=[dir(fullfile(code,'*.m'));dir(fullfile(code,'fas','*.m'))];
entries=struct('file',{},'sha256',{});
for k=1:numel(files)
    path=fullfile(files(k).folder,files(k).name);
    f=fopen(path,'rb'); bytes=fread(f,inf,'*uint8'); fclose(f);
    relative=strrep(path(numel(code)+2:end),'\','/');
    entries(end+1)=struct('file',relative,'sha256',fas_hash(bytes));
end
[~,order]=sort({entries.file}); entries=entries(order);
identity=struct('files',entries,'sha256',fas_hash(unicode2native(jsonencode(entries),'UTF-8')));
end
