module serialize.write;

import serialize.types;
import serialize.status;

import std.bitmanip;
import std.traits;
import std.experimental.allocator;
import std.experimental.logger;
import std.experimental.allocator.mallocator;
import core.memory;

struct IWriteStream(Allocator = Mallocator)
{
	this(size_t size)
	{
		_data = cast(ubyte[]) _alloc.allocate(size);
	}

	static if (stateSize!Allocator != 0)
	{
		this(uint size, Allocator alloc)
		{
			this._alloc = alloc;
			this(size);
		}
	}

	~this()
	{
		if (_data.ptr)
		{
			_alloc.deallocate(_data);
		}
	}

	void write(X)(X value) if(isBasicSupport!(X).isNum)
	{
		doIsArray(dtTypes!X);
		ubyte[X.sizeof] data = nativeToBigEndian!X(value);
		append(data);
	}

	void write(X)(X value) if(isBasicSupport!(X).isChar)
	{
		doIsArray(dtTypes!X);
		append(cast(ubyte)value);
	}

	void write(X:bool)(X value) 
	{
		doIsArray(dtTypes!X);
		ubyte a = value ? 0x01 : 0x00;
		append(a);
	}

	void write(X:DateTime)(ref X value) 
	{
		doIsArray(dtTypes!X);
		ubyte[2] data;
		data = nativeToBigEndian!short(value.year());
		append(data);
		append(value.month());
		append(value.day());
		append(value.hour());
		append(value.minute());
		append(value.second());
	}

	void write(X:Date)(ref X value) 
	{
		doIsArray(dtTypes!X);
		ubyte[2] data;
		data = nativeToBigEndian!short(value.year());
		append(data);
		append(value.month());
		append(value.day());
	}

	void write(X:Time)(ref X value) 
	{
		doIsArray(dtTypes!X);
		append(value.hour);
		append(value.minute);
		append(value.second);
		ubyte[2] data;
		data = nativeToBigEndian!ushort(value.msecond);
		append(data);
	}


	void write(X:char[])(ref X value)
	{
		writeRawArray(Types.Char,cast(ubyte[])value);
	}

	void write(X:byte[])(ref X value)
	{
		writeRawArray(Types.Byte,cast(ubyte[])value);
	}

	void write(X:ubyte[])(ref X value)
	{
		writeRawArray(Types.UByte,value);
	}

	void write(X: string)(ref X value)
	{
		writeRawArray(Types.Char,cast(ubyte[])value);
	}

	void write(X)(ref X value) if(isArray!(X) && isBasicSupport!(X).isBSupport && !isStruct!X)
	{
		startArray!(ForeachType!X)();
		scope(success)endArray();
		foreach(ref v ; value)
		{
			write(v);
		}
	}

	void startArray(X)() if(isBasicSupport!(X).isBSupport)
	{
		Types ty = dtTypes!X;
		StatusNode * state = new StatusNode();
		state.state = Status.InArray;
		state.type = ty;
		_status.push(state);
		append(Types.Array);
		append(ty);
		state.begin = _len;
		ubyte[4] data;
		append(data);
	}

	void endArray()
	{
		StatusNode * state = _status.pop();
		if(state is null || state.state != Status.InArray)
			throw new Exception("not in Array!!!");
		
		scope(exit)GC.free(state);
		ubyte[4] data = nativeToBigEndian!uint(state.len);
		_data[state.begin..(state.begin + 4)] = data;
		append(Types.End);

		StatusNode * state2 = _status.front();
		if(state2 !is null && state2.state == Status.InArray)
		{
			if(state2.type == Types.Array) {
				state2.len ++;
			}
		}
	}

	void startStruct()
	{
		StatusNode * state = new StatusNode();
		state.state = Status.InStruct;
		state.type = Types.Struct;
		_status.push(state);
		append(Types.Struct);
	}

	void endStruct()
	{
		StatusNode * state = _status.pop();

		if(state is null || state.state != Status.InStruct)
			throw new Exception("not in struct!!!");
		scope(exit)GC.free(state);
		append(Types.End);
		StatusNode * state2 = _status.front();
		if(state2 !is null && state2.state == Status.InArray)
		{
			if(state2.type == Types.Struct) {
				state2.len ++;
			}
		}
	}

	pragma(inline) void append(ubyte value)
	{
		if (full)
			exten(1);
		_data[_len] = value;
		++_len;
	}

	pragma(inline) void append(in ubyte[] value)
	{
		//trace("data.length = ", _data.length, "  will len = ",(_len + value.length));
		if (_data.length < (_len + value.length))
			exten(value.length);
		auto len = _len + value.length;
		_data[_len .. len] = value[];
		_len = len;
	}

	pragma(inline) @property ubyte[] dup()
	{
		auto list = new ubyte[length];
		list[0 .. length] = _data[0 .. length];
		return list;
	}

	pragma(inline) ubyte[] data(bool rest = true)
	{
		auto list = _data[0 .. length];
		if (rest)
		{
			_data = null;
			_len = 0;
		}
		return list;
	}

	pragma(inline, true) const @property size_t length()
	{
		return _len;
	}

	pragma(inline, true) void clear()
	{
		_len = 0;
	}

private:
	//pragma(inline, true) 
	void writeRawArray(Types ty, ubyte[] data)
	{
		append(Types.Array);
		append(ty);
		uint leng = cast(uint)data.length;
		ubyte[4] dt = nativeToBigEndian!uint(leng);
		append(dt);
		
		append(data);
		append(Types.End);
	}

	//pragma(inline, true) 
	void doIsArray(Types ty)
	{
		StatusNode * state = _status.front();
		if(state !is null && state.state == Status.InArray)
		{
			if(state.type == ty) {
				state.len ++;
			}else {
				endArray();
				append(ty);
			}
		}else{
			append(ty);
		}
	}

private:
	pragma(inline, true) 
	bool full()
	{
		return length >= _data.length;
	}
	
	void exten(size_t len)
	{
		auto size = _data.length + len;
		if (size > 0)
			size = size > 128 ? size + ((size / 3) * 2) : size * 2;
		else
			size = 32;
		auto data = _data;
		_data = cast(ubyte[]) _alloc.allocate(size);
		_data[0..data.length] = data[];
		_alloc.deallocate(data);
	}

private:
	static if (stateSize!Allocator == 0)
		alias _alloc = Allocator.instance;
	else
		Allocator _alloc;

	size_t _len = 0;
	ubyte[] _data = null;

	StatusStack _status;
}

