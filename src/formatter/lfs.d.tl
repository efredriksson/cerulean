local record lfs
    attributes: function(path: string, attr: string): string, string
    dir: function(path: string): function(): string
    currentdir: function(): string
    chdir: function(path: string): boolean, string
end

return lfs
