const CHUNK_SIZE = 2048;

export class BinaryWriter {
	constructor() {
		this.offset = 0;
		this.buffer = Buffer.alloc(CHUNK_SIZE);
	}
	
	writeUnicode(data) {
		let len = Buffer.byteLength(data);
		this.prealloc(len + 2);
		this.writeUInt16(len);
		this.offset += this.buffer.write(data, this.offset);
		return this;
	}
	
	write(data) {
		if (Buffer.isBuffer(data)) {
			this.prealloc(data.length);
			this.offset += data.copy(this.buffer, this.offset, 0, data.length);
		} else {
			this.prealloc(Buffer.byteLength(data));
			this.offset += this.buffer.write(data, this.offset);
		}
	}
	
	writeChar(c) {
		if (Buffer.byteLength(c) != 1)
			throw new Error(`Multibyte char not supported!`);
		return this.write(c);
	}
	
	writeInt8(i) {
		this.prealloc(1);
		this.offset = this.buffer.writeInt8(i, this.offset);
		return this;
	}
	
	writeUInt8(i) {
		this.prealloc(1);
		this.offset = this.buffer.writeUInt8(i, this.offset);
		return this;
	}
	
	writeInt16(i) {
		this.prealloc(2);
		this.offset = this.buffer.writeInt16BE(i, this.offset);
		return this;
	}
	
	writeUInt16(i) {
		this.prealloc(2);
		this.offset = this.buffer.writeUInt16BE(i, this.offset);
		return this;
	}
	
	writeInt32(i) {
		this.prealloc(4);
		this.offset = this.buffer.writeInt32BE(i, this.offset);
		return this;
	}
	
	writeUInt32(i) {
		this.prealloc(4);
		this.offset = this.buffer.writeUInt32BE(i, this.offset);
		return this;
	}
	
	prealloc(size) {
		if (this.offset + size > this.buffer.length)
			this.buffer = Buffer.concat([this.buffer, Buffer.alloc(Math.max(size, CHUNK_SIZE))]);
	}
	
	data() {
		return this.buffer.slice(0, this.offset);
	}
};
