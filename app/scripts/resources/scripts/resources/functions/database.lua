assert(freeswitch, "Require FreeSWITCH environment");
require "resources.functions.config";



local Database = {};



function Database.new(type, o)
    o = o or {};
    local self = Database;
    self.__index = self;
    self.type = type;
    self:setDsn();
    setmetatable(o, self);
	return o;
end



function Database:setDsn()
    self.dsn = {};
    if (self.type == "system") then
        if (type(database["system"]) == "string") then
            self.dsn.all = database["system"];
        elseif (type(database["system"]) == "table") then
            if (database["system"]["all"]) then
                self.dsn.all = database["system"]["all"];
            else
                if (database["system"]["read"]) then
                    self.dsn.read = database["system"]["read"];
                end
                if (database["system"]["write"]) then
                    self.dsn.write = database["system"]["write"];
                end
            end
        end
    elseif (self.type == "switch") then
        if (file_exists(database_dir.."/core.db")) then
            self.dsn.all = "sqlite://"..database_dir.."/core.db";
        else
            self.dsn.all = database["switch"];
        end
    end

    if (not self.dsn.all and (not self.dsn.read or not self.dsn.write)) then
        freeswitch.consoleLog("err", error("Cannot connect to database no DSN set"));
    end
end



function Database:connect(mode)

    -- call freeswitch.Dbh only when need a new connection
    -- even without this code freeswitch would compare the dsn with other connections
    -- and create a new handle only when it doesn't already have an open connection
    -- with this code we avoid havig to run that extra code each time we call dbh:query()
    if (self:connected()) then 
        if (mode == self.mode) then
            -- connection still the same
            return
        else
            if (self.dsn.read ~= self.dsn.write) then
                -- connection is about to change release old handle (in case of a long running script)
                self:release();
            else
                -- connection the same, read and write have the same dsn
                return
            end
        end
    end

    if (self.dsn.all) then
        self.dbh = freeswitch.Dbh(self.dsn.all);
    else
        if (mode == "r") then
            self.dbh = freeswitch.Dbh(self.dsn.read);
        elseif (mode == "w") then
            self.dbh = freeswitch.Dbh(self.dsn.write);
        end
    end
    
    self.mode = mode;
    assert(self:connected());
end



function Database:connected()
    return self.dbh and self.dbh:connected();
end



function Database:query(sql, ...)

    local mode;
    local params;
    local cb;
    local statement = sql:match("%w+"):lower();

    --get the params and callback argments
    local argc = select('#', ...);
    local i = argc;
   
    if (i > 0) then
        local arg = select(i, ...);
        if (type(arg) == "function" or arg == nil) then
            cb = select(i, ...);
            i = i - 1;
        end
    end
    if (i > 0) then
        local arg = select(i, ...);
        if (type(arg) == "table" or arg == nil) then
            params = select(i, ...);
            i = i - 1;
        end
    end
    assert(i == 0, 'invalid argument #' .. tostring(i))

    if (params) then
        sql, err = sqlApplyParams(sql, params);
        if err then 
            return
        end
    end

    if (statement == "select") then
        mode = "r";
    else
        mode = "w";
    end

    self:connect(mode);

    if (cb) then
        self.dbh:query(sql, cb);
    else
        self.dbh:query(sql);
    end
end



function Database:first_value(sql, params)
    local result;
    self:query(sql, params, function(row)
        result = row
        return 1
    end)
    if not result then return end
    local _, value = next(result); 
    return value;
end



function Database:affected_rows()
    return self.dbh and self.dbh:affected_rows();
end



function Database:release()
    if self.dbh then 
        self.dbh:release();
    end
end



--use emulation of parameters
function sqlApplyParams(sql, params)
    local err;
    local params = params or {};
    local param_pattern = "%f[%a%d:][:]([%a][%a%d_]*)";

    local sql = sql:gsub(param_pattern, function(param)
        local value = params[param];
        local param_type = type(params[param]);

        if param_type == "string" then return sqlQuote(value);
        elseif param_type == "number" then return tostring(value);
        elseif param_type == "boolean" then return value and '1' or '0'; 
        else err = true end

        if err then
            freeswitch.consoleLog("err", "can not bind parameter: undefined parameter: ".. tostring(param));
        end
    end);

    if (err) then
        return nil, err;
    else
        return sql;
    end
end



function sqlEscapeQuotes(str)
    return str:gsub("'", "''");
end



function sqlQuote(sql)
    return string.format("'%s'", sqlEscapeQuotes(sql));
end



return Database;
