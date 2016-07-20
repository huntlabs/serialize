module serialize.read;

import serialize.types;
import serialize.status;

import std.bitmanip;
import std.datetime;
import std.traits;
import core.memory;

import std.stdio;
import std.string;

struct ReadStream
{
	@disable this();

	this(ubyte[] data)
	{
		_data = data;
	}

	Types nextType()
	{
		return cast(Types)(_data[_currt]);
	}

	Types arrayType()
	in{
		assert(_data[_currt] == Types.Array);
	}body{
		return cast(Types)(_data[_currt + 1]);
	}

	// return len.
	uint startReadArray()
	in{
		assert(_data[_currt] == Types.Array);
	}body{
		StatusNode * state = new StatusNode();
		state.state = Status.InArray;
		state.type = cast(Types)_data[_currt+1];
		_status.push(state);

		_currt += 2;
		size_t start = _currt;
		_currt += 4;
		ubyte[4] data;
		data[] = _data[start.._currt];
		return bigEndianToNative!(uint,uint.sizeof)(data);
	}

	void endReadArray()
	{
		_currt ++;
		_status.pop();
	}

	void startReadStruct()
	in{
		assert(_data[_currt] == Types.Struct);
	}body{
		_currt ++;

		StatusNode * state = new StatusNode();
		state.state = Status.InStruct;
		state.type = Types.Struct;
		_status.push(state);
	}

	void endReadStruct()
	{
		_currt ++;
		_status.pop();
	}

	auto read(X)() if(isBasicSupport!(X).isNum)
	{
		typePrev(dtTypes!X);
		size_t start = _currt;
		_currt += X.sizeof;
		ubyte[X.sizeof] data = _data[start.._currt];
		return bigEndianToNative!(X,X.sizeof)(data);
	}
	
	auto read(X)() if(isBasicSupport!(X).isChar)
	{
		typePrev(dtTypes!X);
		X v = _data[_currt];
		++_currt;
		return v;
	}
	
	bool read(X:bool)() 
	{
		typePrev(dtTypes!X);
		ubyte v = _data[_currt];
		++_currt;
		return v > 0;
	}
	
	DateTime read(X:DateTime)() 
	{
		typePrev(dtTypes!X);
		DateTime dt;
		size_t start = _currt;
		_currt += 2;
		ubyte[2] data = _data[start.._currt];
		dt.year(bigEndianToNative!(short)(data));
		dt.month(cast(Month)(_data[_currt]));
		++_currt;
		dt.day(_data[_currt]);
		++_currt;

		dt.hour(_data[_currt]);
		++_currt;
		dt.minute(_data[_currt]);
		++_currt;
		dt.second(_data[_currt]);
		++_currt;

		return dt;
	}
	
	Date read(X:Date)() 
	{
		typePrev(dtTypes!X);
		Date dt;
		size_t start = _currt;
		_currt += 2;
		ubyte[2] data = _data[start.._currt];
		dt.year(bigEndianToNative!(short)(data));
		dt.month(cast(Month)(_data[_currt]));
		++_currt;
		dt.day(_data[_currt]);
		++_currt;
		
		return dt;
	}
	
	Time read(X:Time)() 
	{
		typePrev(dtTypes!X);
		Time tm;
		tm.hour = _data[_currt];
		++_currt;
		tm.minute = _data[_currt];
		++_currt;
		tm.second = _data[_currt];
		++_currt;

		size_t start = _currt;
		_currt += 2;
		ubyte[2] data = _data[start.._currt];
		tm.msecond = bigEndianToNative!(ushort)(data);
		
		return tm;
	}
	
	ubyte[] read(X:ubyte[])()
	in{
		assert(Types.Array == _data[_currt]);
		assert(Types.UByte == _data[_currt + 1]);
	}body{
		uint len = startReadArray();
		size_t start = _currt;
		_currt += len;
		ubyte[] data = _data[start.._currt].dup;
		endReadArray();
		return data;
	}
	
	string read(X: string)()
	in{
		assert(Types.Array == _data[_currt]);
		assert(Types.Char == _data[_currt + 1]);
	}body{
		uint len = startReadArray();
		size_t start = _currt;
		_currt += len;
		ubyte[] data = _data[start.._currt].dup;
		endReadArray();
		return cast(string)data;
	}
	
	X read(X)() if(isArray!(X) && isBasicSupport!(X).isBSupport && !isStruct!X)
	{
		uint leng = startReadArray();
		scope(success)endReadArray();
		mixin("auto value = new " ~ (ForeachType!X).stringof ~ "[leng];");
		foreach(i; 0..leng)
		{
			value[i] = read!(ForeachType!X)();
		}
		return value;
	}

private:
	pragma(inline, true)
	void typePrev(Types ty)
	{
		StatusNode * state2 = _status.front();
		if(state2 is null)
		{
			assert(ty == _data[_currt]);
			++_currt;
		} 
		else if(state2.state != Status.InArray)
		{
			assert(ty == _data[_currt]);
			++_currt;
		}
		else
		{
			assert(ty == state2.type);
		}
	}
private:
	ubyte[] _data;
	size_t _currt;

	StatusStack _status;
}
