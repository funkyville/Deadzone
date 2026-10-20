const Joi = require('joi');

const registerSchema = Joi.object({
  username: Joi.string().alphanum().min(3).max(30).required()
    .messages({ 'string.alphanum': 'Username must be alphanumeric' }),
  email: Joi.string().email().required(),
  password: Joi.string().min(6).max(128).required(),
  continent_id: Joi.number().integer().min(1).max(6).optional()
    .messages({ 'number.base': 'continent_id must be an integer (1-6)' }),
});

const loginSchema = Joi.object({
  email: Joi.string().email().required(),
  password: Joi.string().required(),
});

const resourcesUpdateSchema = Joi.object({
  food: Joi.number().integer().min(0).optional(),
  metal: Joi.number().integer().min(0).optional(),
  ammo: Joi.number().integer().min(0).optional(),
  hard_currency: Joi.number().integer().min(0).optional(),
}).min(1).messages({ 'object.min': 'Provide at least one resource to update' });

const resourcesIncrementSchema = Joi.object({
  resource: Joi.string().valid('food', 'metal', 'ammo', 'hard_currency').required(),
  amount: Joi.number().integer().required(), // can be negative for consumption
});

const sessionCreateSchema = Joi.object({
  x: Joi.number().required().description('X coordinate'),
  y: Joi.number().required().description('Y coordinate'),
  zone: Joi.string().max(50).optional(),
  status: Joi.string().valid('online', 'idle', 'in_combat', 'offline').optional(),
  health: Joi.number().integer().min(0).max(100).optional(),
});

const coordinatesUpdateSchema = Joi.object({
  x: Joi.number().required(),
  y: Joi.number().required(),
  zone: Joi.string().max(50).optional(),
  status: Joi.string().valid('online', 'idle', 'in_combat', 'offline').optional(),
});

function validate(schema) {
  return (req, res, next) => {
    const { error, value } = schema.validate(req.body, { abortEarly: false, stripUnknown: true });
    if (error) {
      return res.status(400).json({
        success: false,
        message: 'Validation failed',
        errors: error.details.map(d => ({ field: d.path.join('.'), message: d.message })),
      });
    }
    req.body = value;
    next();
  };
}

module.exports = {
  registerSchema,
  loginSchema,
  resourcesUpdateSchema,
  resourcesIncrementSchema,
  sessionCreateSchema,
  coordinatesUpdateSchema,
  validate,
};
